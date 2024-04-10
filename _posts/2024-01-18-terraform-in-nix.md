---
layout: post
title: Terraform in Nix
date:   2024-01-18
categories: cloud
---

# Terraform in Nix
---
Here is a technique for managing terraform environments via [nix](https://nixos.org/).

This approach provides a guaranteed terraform and provider dependency version match which may be used as reproducible and convenient development environment. 

Additionally, using the nix build system, we may generate oci images from this environment, allowing for stronger integrity guarantees between local testing and remote runs.

## Background
We 'll denote a terraform environment as a fixed composition of the terraform binary and the source dependencies (i.e. modules) and providers required during runtime.

Such a composition is commonly achieved via a custom Dockerfile, through the use of a pre-made [image](https://hub.docker.com/r/hashicorp/terraform) or an auxiliary utility such as [tfenv](https://github.com/tfutils/tfenv), [tgswitch](https://github.com/warrensbox/tgswitch) or alike.

It is desirable and often necessary to guarantee a reproducible composition of the above in order to provide accurate and error free infrastructure management.

## Approach
We define a `default.nix` file for our terraform environment which includes the terraform binary itself, a set of several providers addons and two targets of `terraformShell` and `terraformImage`.

```nix
{ pkgs }:
let
  tf = pkgs.terraform.withPlugins(plugin: [
    plugin.aws
    plugin.tls
    plugin.cloudinit
    plugin.kubernetes
    plugin.helm
    plugin.time
    plugin.kubectl
  ]);

  terraformShell = pkgs.mkShell rec {
      buildInputs = [ tf ];
      shellHook = ''
        echo "[...] hello world"
        terraform version
        '';
      };
      
  terraformImage = pkgs.dockerTools.buildImage {
    name = "example-tf-image";
    tag  = "latest";
    copyToRoot = [ tf ];
    config     = {
      Cmd = [ "${tf}/bin/terraform" ];
    };
  };
in
{
  inherit terraformShell; 
  inherit terraformImage;
}
```
_default.nix_

### Usage
Creating a local shell environment is like so. 
```bash
$ nix develop .\#terraformShell
[...] hello world
Terraform v1.6.4-dev
on linux_amd64

$ which terraform
/nix/store/5fkgbf281sidcxqad1ia9xkyfnrrn3ci-terraform-1.6.4/bin/terraform  
```

Creating an image from this environment is like so.
```bash
$ nix build .\#images.x86_64-linux.terraformImage
$ docker load < result
Loaded image: example-tf-image:latest
```

The resulting image is optimal in size, only the required dependencies are baked in akin to [google/distroless](https://github.com/GoogleContainerTools/distroless). 

See [#image-composition](#image-composition).

 
### Flakes

Next, we define a `flake.nix` in order to pin the build recipes (i.e. [nix-derivations](https://nixos.org/manual/nix/stable/language/derivations.html)) of our environment above. 

The flake will write to a `flake.lock` which will reference a specific commit in [github:nixpkgs](https://github.com/NixOS/nixpkgs). This in effect pins all dependencies required to recreate this environment recursively from source.

This complete example shows handling of terraform's BSL license and [flake-utils](https://github.com/numtide/flake-utils), a helper for multi architecture support.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils/v1.0.0";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfreePredicate = pkg: builtins.elem(nixpkgs.lib.getName pkg)[
            "terraform"
          ];
        };
      };

      defaultPackage = import ./default.nix { inherit pkgs; };
    in {
      devShells = {
        terraformShell = defaultPackage.terraformShell;
      };

      images = {
        terraformImage = defaultPackage.terraformImage;
      };
    });
}
```
_flake.nix_

The resulting lockfile.

```nix
    "nixpkgs": {
      "locked": {
        "lastModified": 1709309926,
        "narHash": "sha256-VZFBtXGVD9LWTecGi6eXrE0hJ/mVB3zGUlHImUs2Qak=",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "79baff8812a0d68e24a836df0a364c678089e2c7",
        "type": "github"
      },
      "original": {
        "owner": "NixOS",
        "ref": "nixos-23.11",
        "repo": "nixpkgs",
        "type": "github"
      }
    },
```
_snippet of a flake.lock_

## Dependency Resolution in Nix
During execution nix will attempt to fetch pre-compiled binaries from cache.nixos.org, this is an S3 bucket with a clever composition.

* [https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform/default.nix](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform/default.nix).

* [https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform-providers/providers.json](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform-providers/providers.json).



## Image Composition
Users new to nix may find it insightful to explore the resulting OCI image. All binaries and dependencies deterministically resolved from `/nix/store`, the runtime is composed of symbolic links and `PATH` manipulation.

```
├── bin
│   └── terraform
├── libexec
│   └── terraform-providers
│       └── registry.terraform.io
│           ├── gavinbunney
│           │   └── kubectl
│           │       └── 1.14.0
│           │           └── linux_amd64
│           │               └── terraform-provider-kubectl_1.14.0
│           └── hashicorp
│               ├── aws
│               │   └── 5.25.0
│               │       └── linux_amd64
│               │           └── terraform-provider-aws_5.25.0
│               ├── cloudinit
│               │   └── 2.3.2
│               │       └── linux_amd64
│               │           └── terraform-provider-cloudinit_2.3.2
│               ├── helm
│               │   └── 2.11.0
│               │       └── linux_amd64
│               │           └── terraform-provider-helm_2.11.0
│               ├── kubernetes
│               │   └── 2.23.0
│               │       └── linux_amd64
│               │           └── terraform-provider-kubernetes_2.23.0
│               ├── time
│               │   └── 0.9.1
│               │       └── linux_amd64
│               │           └── terraform-provider-time_0.9.1
│               └── tls
│                   └── 4.0.4
│                       └── linux_amd64
│                           └── terraform-provider-tls_4.0.4
└── nix
    └── store
        ├── 0iwvi1hmv7agm3hb53qifd5053z85fpn-terraform-provider-kubernetes-2.23.0
        │   └── libexec
        │       └── terraform-providers
        │           └── registry.terraform.io
        │               └── hashicorp
        │                   └── kubernetes
        │                       └── 2.23.0
        │                           └── linux_amd64
        │                               └── terraform-provider-kubernetes_2.23.0
        ├─⊕ 1zy01hjzwvvia6h9dq5xar88v77fgh9x-glibc-2.38-44
        ├─⊕ 29691038dnsk07w5jr32rw6vsnmarcb5-acl-2.3.1
        ├─⊕ 33h05bypn4cjp3854l4bsd9zdby59imj-iana-etc-20230316
        ├─⊕ 3dfyf6lyg6rvlslvik5116pnjbv57sn0-libunistring-1.1
        ├─⊕ 5fkgbf281sidcxqad1ia9xkyfnrrn3ci-terraform-1.6.4
        ├─⊕ a3n1vq6fxkpk5jv4wmqa1kpd3jzqhml9-libidn2-2.3.4
        ├─⊕ a3zlvnswi1p8cg7i9w4lpnvaankc7dxx-gcc-12.3.0-lib
        ├─⊕ dcnpmf4l1r19snijwirrmcvhwzrgy1dx-terraform-provider-kubectl-1.14.0
        ├─⊕ hcpzsz292pidl02ig5rb1583apcanhj6-mailcap-2.1.53
        ├─⊕ i6nk8llh46f2xjzc5h8j83kwwr1w3kx0-tzdata-2024a
        ├─⊕ j6n6ky7pidajcc3aaisd5qpni1w1rmya-xgcc-12.3.0-libgcc
        ├─⊕ j7mwvhhrzg0n6wald3g4c1pyjf02di1q-terraform-provider-cloudinit-2.3.2
        ├─⊕ jc4j7srg3jd8063p8gn4ib7gp51sb5iy-terraform-provider-helm-2.11.0
        ├─⊕ l0ydz31lwa97zickpsxj2vmprcigh1m4-gcc-12.3.0-libgcc
        ├─⊕ l32763bzsl8vi889gd0yfg56cac1d967-terraform-1.6.4
        ├─⊕ n9h29184cgybwpx8jl5gvsx8g367pksa-attr-2.5.1
        ├─⊕ p3zhf82f9i2bd7yzy258d9xq5bik8nmk-gmp-with-cxx-6.3.0
        ├─⊕ r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15
        ├─⊕ rk067yylvhyb7a360n8k1ps4lb4xsbl3-coreutils-9.3
        ├─⊕ s8c8a8cnypslx9pdfqmijsyjq7dih8bg-terraform-provider-tls-4.0.4
        ├─⊕ vb6w8s0051qqyc3s0lpcx8w1jmysypz9-terraform-provider-time-0.9.1
        └─⊕ w3lb5crpygn59jv43bna7vharrj30zjr-terraform-provider-aws-5.25.0

```
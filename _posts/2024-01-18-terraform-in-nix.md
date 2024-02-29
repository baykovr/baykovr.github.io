---
layout: post
title: Terraform in Nix
date:   2024-01-18
categories: cloud
---

# Terraform in Nix
---
![gpts-idea-of-hand-planes](/assets/gpt-planes.png){:class="img-small-right"}
This past year I have been using a fair bit of [nix](https://nixos.org) at [integrated reasoning](https://reason.ing).
In this post we will explore using nix as a type of virtual environment (specifically nix-shell) for terraform workflows.
We will cover shell composition and provider management, which in my opinion is a unique and interesting attribute, as as operation and docker interoperability.
#--

## Background
When working with terraform I typically use [tfenv](https://github.com/tfutils/tfenv) and a docker image which matches the build system. The image is particularly useful when debugging across multiple environments. But even if you do not use a build/deploy server, the team will benefit from using the exact same tools.

Having recently finished a small nix workflow for a python + lambda environment, I wanted to find out what benefits could be brought to terraform.


Volume mounting `~/.aws/credentials` a remote state storage and [AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html) can get us very close to the CI system environment - all prior to commiting our code for testing.

Additionally I usually use makefiles to wrap commands I would normally type by hand. This allows me to add utilities into the workflow such as [tfsec](https://github.com/aquasecurity/tfsec), generate documentation and eliminate having to remember commands. This does wonders for portability to other users.

```bash
#!/usr/bin/make -f
.PHONY: check
check:
  @tfsec

.PHONY: apply
apply: check
    terraform apply -var-file=secrets.tfvars -auto-approve

.PHONY: docs
docs:
    terraform-docs markdown  . > MODULE.md
```
You could use bash instead of make, or CI boilerplate in forms of yaml to achieve the same function. The important part is capturing the commands in an executable format and retaining the ability to test them locally. 

## What does nix do?
In all, nix is a language and a package manager. You can write expressions in nix and execute them to create installable packages. 

There are no requirements on the structure or contents of a nix package.  

One useful property of nix is that all packages are uniquely identified within the /nix/store and the instructions on the production of the package are [readily available](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform/default.nix) and reproducible from source.

We can also install many versions of terraform side by side and manipulate our `$PATH` accordingly, just like `tfenv`.
```bash
$ which terraform
/nix/store/kylhpgcpsd3gwdgnmb59y3ga32dawjpk-terraform-1.6.4/bin/terraform
├── bin
│   └── terraform
└── share
    └── bash-completion
        └── completions
            └── terraform
```

 We can also create packages which contain not only the terraform dependency, but the provider binary as well.
```bash
/nix/store/xhsp5y24yx4l3205l54wnhd91vaxxqa3-terraform-1.6.2
├── bin
│   └── terraform
└── libexec
    └── terraform-providers
        └── registry.terraform.io
            └── hashicorp
                └── aws
                    └── 5.22.0
                        └── linux_amd64
                            └── terraform-provider-aws_5.22.0
```
So far we are at parity with wget and [terraform lock files](https://developer.hashicorp.com/terraform/language/files/dependency-lock).

# Nix Derivations
Much like a Dockerfile, we can use nix to describe a complete environment in a codified format. One way to accomplish this is through the use nix flakes via `flake.nix`. Nix flake syntax can be bewildering to new readers, I'll do my best to build the complexity up slowly.


## Composition
My end goal is still to package up my terraform environment such that it is portable. To accomplish this I will define two `outputs` of a shell and an image. Both will contain an _identical_ version of terraform, but I will use the `shell` locally and need to worry about volume mapping docker anymore - while mainlining consistency.
```nix
outputs ...
  shell = pkgs.mkShell rec {
    buildInputs = [ tf ];
    shellHook = ''
      terraform version
    '';
  };

  image = pkgs.dockerTools.buildImage {
    name = "tf-img";
    tag = "latest";
    copyToRoot = [ tf ];
    config = {
      Cmd = [ "${tf}/bin/terraform" ];
    };
};
```
I define _where_ to fetch this terraform package from within the `inputs` section, referencing the 23.11 release channel of nix packages as the source of this terraform version.

```nix
inputs ...
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
...
    tf = pkgs.terraform.withPlugins(plugin: [
      pkgs.terraform.plugins.aws
    ]);
```
Thus `tf` in this example references a specific terraform package with the aws provider plugin as well.

If we take a look at `flake.lock` we can see the exact repository pins, this can be followed down to the source _and_ it can be used to ensure full consistency in future builds.
```
    "nixpkgs": {
      "locked": {
        "lastModified": 1705458851,
        "narHash": "sha256-uQvEhiv33Zj/Pv364dTvnpPwFSptRZgVedDzoM+HqVg=",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "8bf65f17d8070a0a490daf5f1c784b87ee73982c",
        "type": "github"
      },
      "original": {
        "owner": "NixOS",
        "ref": "nixos-23.11",
        "repo": "nixpkgs",
        "type": "github"
      }
    }
```

## Usage
We can drop into our development shell or docker image readily and irrespective of our local environment.

```bash
$ nix develop .\#shell.x86_64-linux
terraform version
Terraform v1.6.4-dev
on linux_amd64

$ nix build .\#img.x86_64-linux
  flake.lock
  flake.nix
  result -> /nix/store/5rgqbbdam7s6bgbd7jzyj3yb27bgkxyq-docker-image-tf-img.tar.gz

$ docker load < result
Loaded image: tf-img:latest

$ docker run -it tf-img:latest terraform version
Terraform v1.6.4-dev
on linux_amd64
```

# Complete Example
Remember when the exam question was vastly more complicated than the homework problems, using nix is a lot like that.

```nix
{
  description = "an example";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    utils.url = "github:numtide/flake-utils/v1.0.0";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { 
        inherit system;
        config = {
          allowUnfreePredicate = pkg: builtins.elem(nixpkgs.lib.getName pkg)[
            "terraform"
          ];
        };
      };
      tf = pkgs.terraform.withPlugins(plugin: [
        pkgs.terraform.plugins.aws
      ]);
      in 
      {
        shell = pkgs.mkShell rec {
          buildInputs = [ tf ];
          shellHook = ''
            terraform version
          '';
        };

        image = pkgs.dockerTools.buildImage {
          name = "tf-img";
          tag = "latest";
          copyToRoot = [ tf ];
          config = {
            Cmd = [ "${tf}/bin/terraform" ];
          };
        };
      }
  );
}
```

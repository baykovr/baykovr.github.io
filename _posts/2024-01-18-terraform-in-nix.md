---
layout: post
title: Terraform in Nix
date:   2024-01-18
categories: cloud
---

# Terraform in Nix
---
![gpts-idea-of-hand-planes](/assets/gpt-planes.png){:class="img-small-right"}

## About
Presented here is a technique for managing terraform environments via [nix](https://nixos.org/).

This approach provides a guaranteed terraform and provider dependency version match as a shell environment and oci image alike.

The terraform environment is decoupled from the local system, similar to the function virtualenv provides to python, via nix.

An oci image may be generated as a deployable artifact without the need for a Dockerfile, allowing for code reuse.

## Background
We denote a terraform environment as the composition of the terraform binary, source code and source dependencies (i.e. modules) as well as provider binary dependencies.

Such a composition is commonly achieved via a custom Dockerfile, through the use of a pre-made [image](https://hub.docker.com/r/hashicorp/terraform) or an auxiliary utility such as [terragrunt](https://github.com/gruntwork-io/terragrunt). 

It is desirable and often necessary to guarantee a reproducible composition of the above in order to provide accurate and error free infrastructure management.

## Approach
We express our environment via two files, a default.nix and a flake.nix.

The default.nix file expresses the composition of the terraform binary and zero or more provider binaries.

You can find the sources of how terraform itself is served by nix at [https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform/default.nix](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform/default.nix).

Likewise for terraform providers, [https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform-providers/providers.json](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/applications/networking/cluster/terraform-providers/providers.json).

```nix
#default.nix
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
      buildInputs = [
        tf
      ];
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

The flake file provides specification for the sources of the nix dependencies themselves.
```nix
# flake.nix
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


## 

```
```
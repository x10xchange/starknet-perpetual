
<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/starknet-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/starknet-light.png">
  <img alt="Your logo" src="assets/starknet-light.png">
</picture>
</div>

<div align="center">

[![License: Apache2.0](https://img.shields.io/badge/License-Apache2.0-green.svg)](LICENSE)
</div>

# Starknet Perpetual <!-- omit from toc -->

## Table of contents <!-- omit from toc -->

 <!-- omit from toc -->
- [About](#about)
- [Disclaimer](#disclaimer)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Implementation specification](#implementation-specification)
- [Security](#security)


## About
This repo holds the implementation of Staknet Perpetual Trading contracts.  

## Disclaimer
Perpetual is a work in progress.

## Dependencies
- [Rust and Cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html)
- Cairo dependencies such as [Scarb](https://docs.swmansion.com/scarb/) and [Starknet foundry](https://foundry-rs.github.io/starknet-foundry/index.html).

## Installation
Clone the repo and from within the projects root folder run:
```bash
curl https://sh.rustup.rs -sSf | sh
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh
```

## Implementation specification
Specs document found [here](docs/spec.md)

## Security
Starknet Perpetual follows good practices of security, but 100% security cannot be assured. Starknet Perpetual is provided "as is" without any warranty. Use at your own risk.

For more information and to report security issues, please refer to our [security documentation](https://github.com/starkware-libs/starknet-perpetual/blob/main/docs/SECURITY.md).


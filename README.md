
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
- [Getting help](#getting-help)
- [Help make Perpetual better!](#help-make-perpetual-better)
- [Contributing](#contributing)
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

## Getting help

Reach out to the maintainer at any of the following:
- [GitHub Discussions](https://github.com/starkware-libs/starknet-perpetual/discussions)
- Contact options listed on this [GitHub profile](https://github.com/starkware-libs)

## Help make Perpetual better!

If you want to say thank you or support the active development of Starknet Perpetual:
- Add a GitHub Star to the project.
- Tweet about Starknet Perpetual.
- Write interesting articles about the project on [Dev.to](https://dev.to/), [Medium](https://medium.com), or your personal blog.

## Contributing
Thanks for taking the time to contribute! Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make benefit everybody else and are greatly appreciated.

Please read our [contribution guidelines](https://github.com/starkware-libs/starknet-perpetual/blob/main/docs/CONTRIBUTING.md), and thank you for being involved!

## Security
Starknet Perpetual follows good practices of security, but 100% security cannot be assured. Starknet Perpetual is provided "as is" without any warranty. Use at your own risk.

For more information and to report security issues, please refer to our [security documentation](https://github.com/starkware-libs/starknet-perpetual/blob/main/docs/SECURITY.md).


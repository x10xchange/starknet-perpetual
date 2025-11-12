FROM node:slim

# Install required packages
RUN apt-get update && apt-get install -y \
    git \
    curl \
    zsh \
    build-essential \
    vim \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash vscode && \
    chown -R vscode:vscode /home/vscode

# Update npm and install corepack as root
RUN npm install -g npm corepack && \
    chown -R vscode:vscode /usr/local/lib/node_modules

# Switch to non-root user
USER vscode

ENV HOME=/home/vscode
ENV PATH=${PATH}:${HOME}/.local/bin:/usr/local/bin

# Create local bin directory
RUN mkdir -p ${HOME}/.local/bin

# Install oh-my-zsh
RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s 

# Install Starkli
RUN curl --proto '=https' --tlsv1.2 -sSf https://get.starkli.sh | sh -s
ENV PATH=${PATH}:${HOME}/.starkli/bin
RUN starkliup

# Install Scarb
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.12.2

# Install Starknet Foundry
RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh -s
RUN snfoundryup -v 0.49.0


RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

WORKDIR /workspace
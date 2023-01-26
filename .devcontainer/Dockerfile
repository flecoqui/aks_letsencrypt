# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.238.0/containers/python-3/.devcontainer/base.Dockerfile
# [Choice] Python version (use -bullseye variants on local arm64/Apple Silicon): 3, 3.10, 3.9, 3.8, 3.7, 3.6, 3-bullseye, 3.10-bullseye, 3.9-bullseye, 3.8-bullseye, 3.7-bullseye, 3.6-bullseye, 3-buster, 3.10-buster, 3.9-buster, 3.8-buster, 3.7-buster, 3.6-buster
ARG VARIANT="3.10-bullseye"
FROM --platform=linux/amd64 mcr.microsoft.com/vscode/devcontainers/python:0-${VARIANT}
ARG GO_VERSION="1.19.3"
ARG TERRAFORM_VERSION="1.3.6"
ARG TERRAGRUNT_VERSION="0.42.2"

# [Choice] Node.js version: none, lts/*, 16, 14, 12, 10
ARG NODE_VERSION="none"
RUN if [ "${NODE_VERSION}" != "none" ]; then su vscode -c "umask 0002 && . /usr/local/share/nvm/nvm.sh && nvm install ${NODE_VERSION} 2>&1"; fi

# If your pip requirements rarely change, uncomment this section to add them to the image.
RUN /usr/local/bin/python -m pip install --upgrade pip
COPY ./.devcontainer/requirements.txt /tmp/pip-tmp/
RUN pip3 --disable-pip-version-check --no-cache-dir install -r /tmp/pip-tmp/requirements.txt \
    && rm -rf /tmp/pip-tmp

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends cmake ffmpeg

# install npm, typscript, webpack
RUN apt-get update \
    && apt-get install -y git nodejs npm

RUN npm install -g typescript \
    && npm install -g webpack \
    && npm install -g webpack-cli \
    && npm install -g uglifyjs-webpack-plugin \
    && npm install -g @types/jquery \
    && npm install -g http-server \
    && npm install -g forever \
    && npm install -g mermaid.cli

# install .Net 6.0 SDK
#RUN wget https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
#    && dpkg -i packages-microsoft-prod.deb \ 
#    && apt-get update  \
#    && apt-get install -y apt-transport-https \ 
#    && apt-get install -y dotnet-sdk-6.0

# Install Azure CLI
RUN  curl -sL https://aka.ms/InstallAzureCLIDeb  | bash 

# Install Docker CLI
RUN apt-get update \
    && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    dnsutils
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Docker version for bullseye not yet available fall back to eoan 
# RUN echo \
#  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
#  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  eoan stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN  apt-get update \
      && apt-get install -y docker-ce-cli


# install Go
RUN curl -OL https://golang.org/dl/go"${GO_VERSION}".linux-amd64.tar.gz
RUN tar -C /usr/local -xvf go"${GO_VERSION}".linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin:/home/vscode/go/bin

# install shellcheck
RUN wget -qO- "https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz" | tar -xJv \
    && mv "shellcheck-stable/shellcheck" /usr/bin/ \
    && rm -r "shellcheck-stable"

# Install Terraform
RUN curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d "/usr/local/bin" \
    && chmod +x /usr/local/bin/terraform \
    && rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" 

# Install Terragrunt
RUN curl -LO "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64" \
    && mv -f "terragrunt_linux_amd64" "/usr/local/bin/terragrunt" \
    && chmod +x /usr/local/bin/terragrunt

# install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# install helm
RUN curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
RUN  apt-get install apt-transport-https --yes
RUN  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
RUN apt-get update &&  apt-get install -y helm

# install extension for connected k8s
# RUN az extension add --name connectedk8s

# [Optional] Uncomment this line to install global node packages.
# RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && npm install -g <your-package-here>" 2>&1

RUN echo 'source /usr/share/bash-completion/completions/git' >> /home/vscode/.bashrc

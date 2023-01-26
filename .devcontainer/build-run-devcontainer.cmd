REM Run devcontainer locally without VSCode
docker build -f Dockerfile . -t devcontainer-image:latest
docker run   -it --rm -v %~dp0/..:/avworkspace -u vscode -w /avworkspace --name devcontainer devcontainer-image:latest bash

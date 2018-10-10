FROM node:latest

RUN git clone https://github.com/pryorda/ssh-perf && \
    cd ssh-perf && \
    npm install -g . && \
    dd if=/dev/urandom of=/tmp/file1 bs=2048K count=1

ENTRYPOINT ["ssh-perf"]

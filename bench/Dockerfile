FROM node:latest

RUN git clone https://github.com/pryorda/ssh-perf && \
    cd ssh-perf && \
    git checkout 950c6582350c4aa4273f974183733df038963be6 && \
    npm install -g . && \
    dd if=/dev/urandom of=/tmp/file1 bs=2K count=1

ENTRYPOINT ["ssh-perf"]

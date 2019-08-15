FROM openjdk:8u141-jre

RUN apt-get update && apt-get install -y python2.7

RUN curl -L http://archive.apache.org/dist/cassandra/2.2.9/apache-cassandra-2.2.9-bin.tar.gz -o ./cassandra.tar.gz

RUN mkdir cassandra

RUN tar --strip=1 --directory=cassandra -x -f cassandra.tar.gz

COPY mx4j-tools.jar /cassandra/lib

COPY run.sh /

COPY cassandra.yaml /cassandra/conf

RUN chmod +x /run.sh

ENV PATH /cassandra/bin:$PATH

CMD /run.sh

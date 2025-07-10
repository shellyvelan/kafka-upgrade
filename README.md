# Lets Deploy Kafka From Scratch :) 

## High Level Plan

Connect np to new kafka while it's still connected to old one, publish and read from both.

Tweak so new Kafka works smoothly and remove old kafka from np.

Everything smooth? good,moving on.

Once np is in check, start with prod Kirya (since we're in Maof, we’ll start on the one we're not working on), repeat steps. 

DR, then Maof and repeat steps.


## General Step By Step
1. Create swarm: 
    docker swarm init --advertise-addr <MANAGER-IP>

    output-

    Swarm initialized: current node (dxn1zf6l61qsb1josjja83ngz) is now a manager.

    To add a worker to this swarm, run the following command:
```bash
docker swarm join \
--token SWMTKN-1-49nj1cmql0jkz5s954yi3oex3nedyz0fb0xx14ie39trti4wxv-8vxv8rssmk743ojnwacrr2e7c \
192.168.99.100:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```
2. After following this command: ‘docker swarm join-token manager’. Go to the second and third to-be-manager nodes, and follow the          instructions the command gave you.

3. Go to the to-be-worker VMs and add the node to the swarm:
```bash
 docker swarm join \
 --token  SWMTKN-1-49nj1cmql0jkz5s954yi3oex3nedyz0fb0xx14ie39trti4wxv-8vxv8rssmk743ojnwacrr2e7c \
 192.168.99.100:2377

 This node joined a swarm as a worker.
```
    If you lost token, run this command:
    docker swarm join-token worker
    Check swarm status:
    docker node ls

4. Create docker-swarm.yml with the needed services.

5. Deploy stack: 
```bash
docker stack deploy -c docker-swarm.yml kafka
```
6. Upload all connectors to the new Kafka connect server. (use scripts we already have with that same jsons, just need to update to what cluster to connect to and add the -u flag)

7. Update consumers config map to point to new Kafka servers (plus add certificates for authentication, we’ll talk about it below).


## Where will each component be placed and how many nodes do we need?

We need 5 controllers, and they need to be on separate nodes. This immediately means 5 dedicated nodes for controllers. And we want 3 brokers, and they need to be on separate nodes from each other and from the controllers. This means 3 dedicated nodes for brokers.
Ideally 2 instances of schema registry, 2 instances of connect, they all can share nodes, so each instance can be on a node, so 2 dedicated nodes.

As well as 3 Docker Swarm manager nodes, BP to let them manage the cluster, not run any tasks, so that is another 3 dedicated nodes. 
Ideally 13 nodes for the cluster. 

3 manager nodes- don't need the massive storage/CPU of brokers.

5 worker nodes for kraft controllers.

3 worker nodes for brokers- require more significant resources.

2 worker nodes for connect.


## Cluster stats

Client to Broker: SSL (SSL encryption only, with mTLS)

Broker to Broker: SSL (SSL encryption only, with mTLS)

Controller to Controller: SSL (SSL encryption only, with mTLS) (REST api with basic auth https)


## Step By Step

1. Generate uuid for cluster: 
```bash
    docker run --rm confluentinc/cp-kafka:7.9.0 kafka-storage.sh random-uuid
```
2. Generate CAs with the script in the project:
    generate-certs.sh

3. Deploy the swarm yml (only controller has replica=1)

    Make sure all controller nodes are up and we have a leader before continuing (ssl connections etc').

4.  
```bash
    docker service scale kafka_kafka-broker-0=1
    docker service scale kafka_kafka-broker-1=1 
    docker service scale kafka_kafka-broker-2=1
```
    (make sure everything is good including ssl connections and that you can see "Kafka Server started (kafka.server.KafkaRaftServer)" in the logs)

5. Run acl script: acl-script.sh

6. docker service scale kafka_kafka-connect=1 (for both replicas)

7. Add test mongo-connector by running scripts/add-mongodb-source-connector.sh (test with db and stuff)

8. docker service scale kafka_akhq=1


## KafkaJS Authentication And Encryption:




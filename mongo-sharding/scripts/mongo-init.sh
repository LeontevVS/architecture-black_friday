#!/bin/bash

wait_for_primary() {
    local container=$1
    local port=$2
    echo "Waiting for Primary in $container..."
    for i in {1..60}; do
        echo "try $i/60"
        if docker compose exec -T "$container" mongosh --port "$port" --quiet --eval 'if (rs.status().myState === 1) { quit(0) } else { quit(1) }' > /dev/null 2>&1; then
            echo "$container is Primary"
            return 0
        fi
        sleep 2
    done
    echo "Timeout waiting for $container"
    return 1
}

docker compose exec -T configSrv1 mongosh --port 27017 <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv1:27017" },
      { _id : 1, host : "configSrv2:27018" },
      { _id : 2, host : "configSrv3:27019" }
    ]
  }
);
EOF

wait_for_primary configSrv1 27017

docker compose exec -T shard1 mongosh --port 27020 <<EOF
rs.initiate(
  {
    _id : "shard1",
    members: [
      { _id : 0, host : "shard1:27020" }
    ]
  }
);
EOF

wait_for_primary shard1 27020

docker compose exec -T shard2 mongosh --port 27021 <<EOF
rs.initiate(
  {
    _id : "shard2",
    members: [
      { _id : 0, host : "shard2:27021" }
    ]
  }
);
EOF

wait_for_primary shard2 27021

docker compose exec -T mongos_router mongosh --port 27022 <<EOF
sh.addShard("shard1/shard1:27020");
sh.addShard("shard2/shard2:27021");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" })

use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

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

docker compose exec -T shard1-repl1 mongosh --port 27020 <<EOF
rs.initiate(
  {
    _id : "shard1",
    members: [
      { _id : 0, host : "shard1-repl1:27020" },
      { _id : 1, host : "shard1-repl2:27021" },
      { _id : 2, host : "shard1-repl3:27022" }
    ]
  }
);
EOF

docker compose exec -T shard2-repl1 mongosh --port 27023 <<EOF
rs.initiate(
  {
    _id : "shard2",
    members: [
      { _id : 0, host : "shard2-repl1:27023" },
      { _id : 1, host : "shard2-repl2:27024" },
      { _id : 2, host : "shard2-repl3:27025" }
    ]
  }
);
EOF

wait_for_primary configSrv1 27017
wait_for_primary shard1-repl1 27020
wait_for_primary shard2-repl1 27023

docker compose exec -T mongos_router mongosh --port 27026 <<EOF
sh.addShard("shard1/shard1-repl1:27020");
sh.addShard("shard2/shard2-repl1:27023");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" })

use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

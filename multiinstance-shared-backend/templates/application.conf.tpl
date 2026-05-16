play.http.secret.key = ${?THEHIVE_SECRET}
play.http.session.cookieName = "__COOKIE_NAME__"

http.address = "0.0.0.0"
http.port = 9000

db.provider = janusgraph
db.janusgraph {
  storage {
    backend = cql
    hostname = ["cassandra"]
    port = 9042
    cql {
      keyspace = __THEHIVE_KEYSPACE__
      local-datacenter = dc1
      replication-factor = 1
      read-consistency-level = ONE
      write-consistency-level = ONE
    }
  }

  index.search {
    backend = elasticsearch
    hostname = ["elasticsearch:9200"]
    index-name = __THEHIVE_INDEX__
  }
}

storage.provider = localfs
storage.localfs.location = /opt/thp/thehive/files

auth {
  providers = [
    {name = session}
    {name = basic, realm = thehive}
    {name = local}
    {name = key}
  ]
}

akka.http.server.request-timeout = 5 minutes

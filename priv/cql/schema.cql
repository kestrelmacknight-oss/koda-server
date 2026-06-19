CREATE KEYSPACE IF NOT EXISTS koda
  WITH replication = {'class': 'NetworkTopologyStrategy', 'datacenter1': 1}
  AND durable_writes = true;

USE koda;

CREATE TABLE IF NOT EXISTS messages (
  channel_id  UUID,
  bucket      INT,
  id          TIMEUUID,
  sender_id   UUID,
  content     TEXT,
  encrypted   BOOLEAN,
  inserted_at TIMESTAMP,
  PRIMARY KEY ((channel_id, bucket), id)
) WITH CLUSTERING ORDER BY (id DESC)
  AND compaction = {'class': 'TimeWindowCompactionStrategy', 'compaction_window_size': '7', 'compaction_window_unit': 'DAYS'};

CREATE TABLE IF NOT EXISTS dm_messages (
  conversation_id UUID,
  bucket          INT,
  id              TIMEUUID,
  sender_id       UUID,
  content         TEXT,
  encrypted       BOOLEAN,
  inserted_at     TIMESTAMP,
  PRIMARY KEY ((conversation_id, bucket), id)
) WITH CLUSTERING ORDER BY (id DESC)
  AND compaction = {'class': 'TimeWindowCompactionStrategy', 'compaction_window_size': '7', 'compaction_window_unit': 'DAYS'};

CREATE TABLE IF NOT EXISTS message_reactions (
  message_id UUID,
  emoji      TEXT,
  user_id    UUID,
  PRIMARY KEY ((message_id), emoji, user_id)
);

CREATE TABLE IF NOT EXISTS pinned_messages (
  channel_id UUID,
  message_id TIMEUUID,
  pinned_by  UUID,
  pinned_at  TIMESTAMP,
  PRIMARY KEY (channel_id, message_id)
) WITH CLUSTERING ORDER BY (message_id DESC);

CREATE TABLE IF NOT EXISTS last_read (
  user_id    UUID,
  channel_id UUID,
  message_id TIMEUUID,
  PRIMARY KEY (user_id, channel_id)
);

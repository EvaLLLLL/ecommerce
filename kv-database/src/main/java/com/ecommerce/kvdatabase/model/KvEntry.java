package com.ecommerce.kvdatabase.model;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Getter;

/**
 * Represents an immutable key-value entry with versioning and timestamp metadata.
 * <p>
 * Each entry contains a key-value pair along with a version number for optimistic concurrency
 * control and a timestamp indicating when the entry was created. This class is used in a
 * distributed key-value store to track data evolution and resolve conflicts during replication.
 * </p>
 */
public class KvEntry {

  @Getter
  private final String key;

  @Getter
  private final String value;

  @Getter
  private final int version;

  @Getter
  private final long timestamp;

  public KvEntry(String key, String value, int version) {
    this(key, value, version, System.currentTimeMillis());
  }

  @JsonCreator
  public KvEntry(
      @JsonProperty("key") String key,
      @JsonProperty("value") String value,
      @JsonProperty("version") int version,
      @JsonProperty("timestamp") long timestamp) {
    this.key = key;
    this.value = value;
    this.version = version;
    this.timestamp = timestamp;
  }
}
package com.ecommerce.kvdatabase.service;


import com.ecommerce.kvdatabase.model.KvEntry;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class StorageService {

  private static final Logger log = LoggerFactory.getLogger(StorageService.class);

  /**
   * Core storage: Key -> KvEntry
   */
  private final Map<String, KvEntry> repository = new ConcurrentHashMap<>();

  /**
   * Version tracker: Key -> LatestVersion (maintained only when current node acts as coordinator)
   */
  private final Map<String, Integer> versionTracker = new ConcurrentHashMap<>();

  public KvEntry putLocal(String key, String value, int version) {
    sleepQuietly(200);
    KvEntry entry = new KvEntry(key, value, version);
    repository.put(key, entry);
    log.info("Local Storage Updated: key={} v={}", key, version);
    return entry;
  }

  public Optional<KvEntry> getLocal(String key) {
    sleepQuietly(50);
    return Optional.ofNullable(repository.get(key));
  }

  public synchronized int getNextVersion(String key) {
    if (!versionTracker.containsKey(key)) {
      int currentMax = repository.containsKey(key) ? repository.get(key).getVersion() : 0;
      versionTracker.put(key, currentMax);
    }
    int nextVersion = versionTracker.get(key) + 1;
    versionTracker.put(key, nextVersion);
    return nextVersion;
  }

  private void sleepQuietly(int ms) {
    try {
      Thread.sleep(ms);
    } catch (InterruptedException e) {
      log.error("Sleep interrupted", e);
      Thread.currentThread().interrupt();
    }
  }
}
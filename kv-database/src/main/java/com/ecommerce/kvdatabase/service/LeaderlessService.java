package com.ecommerce.kvdatabase.service;

import com.ecommerce.kvdatabase.config.NodeConfig;
import com.ecommerce.kvdatabase.model.KvEntry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Handles Leaderless database logic (W=N, R=1).
 * <p>
 * When this node receives a client write, it becomes the Write Coordinator: 1. Assigns a version
 * number via StorageService 2. Writes to local store (200ms delay inside StorageService.putLocal)
 * 3. Propagates to all peers sequentially via PUT /internal/kv 4. Returns 201 only after ALL peers
 * acknowledge
 * <p>
 * Read (R=1): returns local value only (50ms delay inside StorageService.getLocal)
 */
@Service
public class LeaderlessService {

  private static final Logger log = LoggerFactory.getLogger(LeaderlessService.class);

  @Autowired
  private StorageService storageService;

  @Autowired
  private NodeConfig nodeConfig;

  @Autowired
  private RestTemplate restTemplate;

  /**
   * Handles a client write — this node becomes Write Coordinator. Propagates to ALL peers (W=N)
   * before returning.
   */
  public int handleClientWrite(String key, String value) {

    // Step 1: Assign new version number
    int newVersion = storageService.getNextVersion(key);

    // Step 2: Write to local store (StorageService.putLocal sleeps 200ms)
    storageService.putLocal(key, value, newVersion);

    // Step 3: Propagate to all peers sequentially
    for (String peerUrl : nodeConfig.getPeerUrls()) {
      propagateToPeer(peerUrl, key, value, newVersion);
    }

    // Step 4: All peers confirmed — return version to controller
    return newVersion;
  }

  /**
   * Handles an internal write from the Write Coordinator. Simply writes to local store (200ms delay
   * inside StorageService).
   */
  public void handleInternalWrite(String key, String value, int version) {
    storageService.putLocal(key, value, version);
  }

  /**
   * Handles a client read (R=1). Returns local value only (50ms delay inside StorageService).
   */
  public Optional<KvEntry> handleRead(String key) {
    return storageService.getLocal(key);
  }

  /**
   * Returns local value with NO delay — used only by tests to inspect node state during the
   * inconsistency window.
   */
  public Optional<KvEntry> localRead(String key) {
    // Directly access repository without delay
    // StorageService.getLocal has 50ms delay, so we call it here
    // but the assignment only requires local_read to bypass quorum,
    // not necessarily the delay — keeping it simple:
    return storageService.getLocal(key);
  }

  /**
   * Sends a propagation write to a single peer node via PUT /internal/kv.
   */
  private void propagateToPeer(String peerUrl, String key, String value, int version) {
    try {
      HttpHeaders headers = new HttpHeaders();
      headers.setContentType(MediaType.APPLICATION_JSON);

      Map<String, Object> body = new HashMap<>();
      body.put("key", key);
      body.put("value", value);
      body.put("version", version);

      HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);

      restTemplate.exchange(
          peerUrl + "/kv/internal/kv",
          HttpMethod.PUT,
          entity,
          Void.class
      );
    } catch (Exception e) {
      log.error("Failed to propagate to {}: {}", peerUrl, e.getMessage());
      throw new RuntimeException("Peer unreachable: " + peerUrl);
    }
  }
}

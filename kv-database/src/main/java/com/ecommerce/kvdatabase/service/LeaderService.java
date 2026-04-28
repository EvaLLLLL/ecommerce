package com.ecommerce.kvdatabase.service;

import com.ecommerce.kvdatabase.config.NodeConfig;
import com.ecommerce.kvdatabase.model.KvEntry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.*;

import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
public class LeaderService {

  private static final Logger log = LoggerFactory.getLogger(LeaderService.class);

  @Autowired
  private StorageService storageService;

  @Autowired
  private NodeConfig nodeConfig;

  @Autowired
  private RestTemplate restTemplate;

  // -------------------------
  // PUT (Write)
  // -------------------------
  public int put(String key, String value) {
    int newVersion = storageService.getNextVersion(key);

    List<String> followerUrls = nodeConfig.getFollowerUrls();
    int w = nodeConfig.getWriteQuorumSize();

    // replicate to (W-1) followers sequentially, leader itself counts as 1
    int replicated = 0;
    for (String url : followerUrls) {
      if (replicated >= w - 1) {
        break;
      }
      try {
        sendPutToFollower(url, key, value, newVersion);
        replicated++;
      } catch (Exception e) {
        log.error("Failed to replicate to follower {}: {}", url, e.getMessage());
        throw new RuntimeException("Follower unreachable: " + url);
      }
    }

    // leader writes to its own store last
    storageService.putLocal(key, value, newVersion);

    return newVersion;
  }

  // -------------------------
  // GET (Read)
  // -------------------------
  public KvEntry get(String key) {
    Optional<KvEntry> leaderEntry = storageService.getLocal(key);

    int r = nodeConfig.getReadQuorumSize();
    if (r == 1) {
      return leaderEntry.orElse(null);
    }

    // collect responses from (R-1) followers and return highest version
    List<String> followerUrls = nodeConfig.getFollowerUrls();
    KvEntry latest = leaderEntry.orElse(null);
    int collected = 1; // leader counts as 1

    for (String url : followerUrls) {
      if (collected >= r) {
        break;
      }
      try {
        KvEntry followerEntry = sendGetToFollower(url, key);
        if (followerEntry != null) {
          if (latest == null || followerEntry.getVersion() > latest.getVersion()) {
            latest = followerEntry;
          }
          collected++;
        }
      } catch (Exception e) {
        log.error("Failed to read from follower {}: {}", url, e.getMessage());
        throw new RuntimeException("Follower unreachable: " + url);
      }
    }

    return latest;
  }

  // -------------------------
  // HTTP Helpers
  // -------------------------
  private void sendPutToFollower(String baseUrl, String key, String value, int version) {
    String url = baseUrl + "/kv";
    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);
    Map<String, Object> body = Map.of("key", key, "value", value, "version", version);
    HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);
    restTemplate.exchange(url, HttpMethod.PUT, request, Void.class);
  }

  private KvEntry sendGetToFollower(String baseUrl, String key) {
    String url = baseUrl + "/kv?key=" + key;
    try {
      ResponseEntity<KvEntry> response = restTemplate.getForEntity(url, KvEntry.class);
      return response.getBody();
    } catch (org.springframework.web.client.HttpClientErrorException.NotFound e) {
      // 404 means key not yet replicated — treat as null (stale), not an error
      return null;
    }
  }
}
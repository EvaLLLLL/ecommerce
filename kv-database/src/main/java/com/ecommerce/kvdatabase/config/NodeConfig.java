package com.ecommerce.kvdatabase.config;

import java.time.Duration;
import lombok.Getter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.restclient.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

@Configuration
public class NodeConfig {

  @Getter
  @Value("${kv.role}")
  private String role;

  @Value("${kv.follower-urls}")
  private String followerUrlsRaw;

  @Getter
  @Value("${kv.write-quorum-size}")
  private int writeQuorumSize;

  @Getter
  @Value("${kv.read-quorum-size}")
  private int readQuorumSize;

  @Value("${kv.peer-urls}")
  private String peerUrlsRaw;

  @Getter
  @Value("${kv.node-self-url}")
  private String nodeSelfUrl;

  public boolean isLeader() {
    return "leader".equalsIgnoreCase(role);
  }

  public List<String> getFollowerUrls() {
    if (followerUrlsRaw == null || followerUrlsRaw.isBlank()) {
      return Collections.emptyList();
    }
    return Arrays.asList(followerUrlsRaw.split(","));
  }

  public List<String> getPeerUrls() {
    if (peerUrlsRaw == null || peerUrlsRaw.isBlank()) {
      return Collections.emptyList();
    }
    return Arrays.asList(peerUrlsRaw.split(","));
  }


  @Bean
  public RestTemplate restTemplate(RestTemplateBuilder builder) {
    return builder
        .connectTimeout(Duration.ofSeconds(5))
        .readTimeout(Duration.ofSeconds(15))
        .build();
  }
}

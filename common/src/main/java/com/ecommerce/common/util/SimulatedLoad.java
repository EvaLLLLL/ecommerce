package com.ecommerce.common.util;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Simulates CPU and memory load to trigger auto-scaling.
 * <p>
 * Log-normal parameters for shopping cart operations: μ = ln(300) ≈ 5.70  →  median delay ~300ms σ
 * = 0.8              →  heavy long tail; checkout involves multiple downstream calls so real
 * latency distribution has a wider spread than simpler services.
 */
public class SimulatedLoad {

  private static final double MU = Math.log(300);
  private static final double SIGMA = 0.8;

  public static long logNormalDelayMs() {
    double z = ThreadLocalRandom.current().nextGaussian();
    long delay = (long) Math.exp(MU + SIGMA * z);
    return Math.min(delay, 5000);
  }

  public static void busyWait(long milliseconds) {
    long endTime = System.currentTimeMillis() + milliseconds;
    List<byte[]> memoryHog = new ArrayList<>();
    int allocationCounter = 0;

    while (System.currentTimeMillis() < endTime) {
      double result = 0;
      for (int i = 0; i < 10000; i++) {
        result += Math.sqrt(i) * Math.sin(i) * Math.cos(i);
      }
      if (allocationCounter++ % 100 == 0) {
        memoryHog.add(new byte[1024]);
        if (memoryHog.size() > 1000) {
          memoryHog.removeFirst();
        }
      }
      if (result == Double.MAX_VALUE) {
        System.out.println("Unlikely");
      }
    }
    memoryHog.clear();
  }
}

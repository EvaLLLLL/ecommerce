"""
Locust load test for 5 — E-commerce microservices.

Session model:

    (Browse^k1) → AddItem → (Browse^k2) → AddItem → ... → (Browse^kN) → Terminal

Where:
  - Total AddItem count per session ~ LogNormal(mu=1.1, sigma=0.15), median ≈ 3
  - Browse count before each action  ~ LogNormal(mu=1.3, sigma=0.1),  median ≈ 4
  - Terminal action: Checkout (10%) or Abandon (90%)
  - Quantity per AddItem ~ Uniform(1, 3)

Business-result handling:
  - AddItem  200 → success, 409 (out of stock) → success
  - Checkout 200 → success, 402 (declined) → success, 409 (reserve fail) → success
"""

import os
import random

from locust import HttpUser, LoadTestShape, between, task

# ─── Service Endpoints ───────────────────────────────────────────────────────
# Use Locust --host (see run-all-tests.sh / terraform ALB). Paths hit the same ALB;
# routing is by path (product vs cart).

# ─── Session Parameters ─────────────────────────────────────────────────────
PRODUCT_COUNT = 1000  # Total products pre-loaded via data-loader (IDs 1..N)
CHECKOUT_RATE = 0.10  # 10% checkout, 90% abandon (real-world avg ~70-80% abandon)

# Browse count per add-item slot: median = e^1.3 ≈ 3.7 page views
BROWSE_MU = 1.3
BROWSE_SIGMA = 0.1

# Add-item count per session: median = e^1.1 ≈ 3.0 items
ITEMS_MU = 1.1
ITEMS_SIGMA = 0.15


# ─── Helpers ─────────────────────────────────────────────────────────────────

def sample_lognormal_int(mu: float, sigma: float) -> int:
  """Sample a positive integer from a log-normal distribution (min 1)."""
  return max(1, round(random.lognormvariate(mu, sigma)))


def random_product_id() -> int:
  return random.randint(1, PRODUCT_COUNT)


def random_quantity() -> int:
  return random.randint(1, 3)


def random_credit_card() -> str:
  return "-".join(f"{random.randint(0, 9999):04d}" for _ in range(4))


# ─── Locust User ─────────────────────────────────────────────────────────────

class EcommerceUser(HttpUser):
  wait_time = between(1, 3)

  @task
  def customer_session(self) -> None:
    customer_id = random.randint(1, 100_000)
    total_adds = sample_lognormal_int(ITEMS_MU, ITEMS_SIGMA)

    cart_id: int | None = None
    successful_adds = 0

    for _ in range(total_adds):
      self._browse()
      cart_id, ok = self._add_item(customer_id, cart_id)
      if ok:
        successful_adds += 1

    self._browse()  # final browse before leaving

    if successful_adds > 0 and random.random() < CHECKOUT_RATE:
      self._checkout(cart_id)

  # ── Browse ───────────────────────────────────────────────────────────────

  def _browse(self) -> None:
    for _ in range(sample_lognormal_int(BROWSE_MU, BROWSE_SIGMA)):
      self.client.get(
        f"/products/{random_product_id()}",
        name="/products/[productId]",
      )

  # ── Add Item ─────────────────────────────────────────────────────────────

  def _add_item(self, customer_id: int, cart_id: int | None) -> tuple[
    int | None, bool]:
    with self.client.post(
        "/shopping-carts/addItem",
        json={
          "customer_id": customer_id,
          "product_id": random_product_id(),
          "quantity": random_quantity(),
        },
        name="/shopping-carts/addItem",
        catch_response=True,
    ) as resp:
      if resp.status_code == 200:
        try:
          return resp.json()["shopping_cart_id"], True
        except (ValueError, TypeError, KeyError):
          resp.failure("AddItem response missing shopping_cart_id")
          return cart_id, False

      if resp.status_code == 409:
        resp.success()
        return cart_id, False

      resp.failure(f"AddItem failed: {resp.status_code}")
      return cart_id, False

  # ── Checkout ─────────────────────────────────────────────────────────────

  def _checkout(self, cart_id: int) -> None:
    with self.client.post(
        f"/shopping-carts/{cart_id}/checkout",
        json={"credit_card_number": random_credit_card()},
        name="/shopping-carts/[id]/checkout",
        catch_response=True,
    ) as resp:
      if resp.status_code == 200:
        return
      if resp.status_code in (402, 409):
        resp.success()
        return
      resp.failure(f"Checkout failed: {resp.status_code}")


# ─── Optional Stair-Step Shape (continuous, no reset between steps) ─────────
# Only registered when LOCUST_USE_STAIR_SHAPE=1 (see run-all-tests.sh). Otherwise
# a LoadTestShape that returns None would end the run immediately.
if os.getenv("LOCUST_USE_STAIR_SHAPE", "0") == "1":

  class StairStepShape(LoadTestShape):
    _users = [
      int(v.strip())
      for v in os.getenv("STEP_USERS", "400,800,1200,1500").split(",")
      if v.strip()
    ]
    _step_duration = int(os.getenv("STEP_DURATION", "300"))
    _spawn_rate = float(
      os.getenv("STEP_SPAWN_RATE", os.getenv("SPAWN_RATE", "20"))
    )

    def tick(self):
      run_time = self.get_run_time()
      step_index = int(run_time // self._step_duration)
      if step_index >= len(self._users):
        return None
      return self._users[step_index], self._spawn_rate

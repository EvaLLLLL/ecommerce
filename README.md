# E-commerce distributed microservices & database

## Use Cases and Frequency Assumptions

Session model:

    (Browse^k1) → AddItem → (Browse^k2) → AddItem → ... → (Browse^kN) → Terminal

Where:

- Total AddItem count per session ~ LogNormal(mu=1.1, sigma=0.15), median ≈ 3
- Browse count before each action  ~ LogNormal(mu=1.3, sigma=0.1), median ≈ 4
- Terminal action: Checkout (10%) or Abandon (90%)
- Quantity per AddItem ~ Uniform(1, 3)

Business-result handling:

- AddItem 200 → success, 409 (out of stock) → success
- Checkout 200 → success, 402 (declined) → success, 409 (reserve fail) → success

## System Architecture

**System Architecture Diagram**

![System Architecture](./locust-load-tester/reports-after-5/diagram.png)

**Data flow explanation**

Traffic enters the **public ALB** (:80). **`/products*`** → **Product** (:8080); *
*`/shopping-carts*`** → **Shopping Cart** (:8082).

- **Product** ↔ **Products KV** via **internal NLB** :**8084**.
- **Add item:** Client → **Shopping Cart** (POST `/addItem`, public ALB) → Cart calls **Product** (
  GET weight, public ALB) → Cart calls **Warehouse** :8083 (check inventory, NLB) → Cart writes to *
  *Carts KV** :8085 (NLB).
- **Checkout:** Client → **Shopping Cart** (POST `/checkout`, public ALB) → Cart reads **Carts KV
  ** → Cart calls **Warehouse** (reserve, NLB) → Cart calls **CCA** :8081 (authorize, NLB) → Cart
  commits order to **Carts KV** → Cart publishes ship message to **RabbitMQ** :5672; **Warehouse**
  consumes that queue for fulfillment.

CCA, Warehouse, RabbitMQ, and both KVs are **internal-only** (NLB). **Product**, **Cart**, and **CCA
** scale with ECS target tracking; **Warehouse** stays **one task** (for consistency). Metrics: *
*CloudWatch**.

---

## Database choice

### Products KV — Leader-Follower, N=3, W=3, R=1

**Read-write ratio (~149 : 1).** The Product Service is dominated by read operations. Each AddItem
action requires browsing an average of 3.69 products (Log-Normal μ=1.3, σ=0.1) before selecting one.
With an average of 3.03 AddItem actions per session (Log-Normal μ=1.1, σ=0.15), each session
generates approximately 4.03 browse segments × 3.69 reads = ~14.87 product reads. Since product
writes occur only during initial catalog loading (1,000 products at startup) and are otherwise
negligible, the Product database experiences an estimated read-to-write ratio of approximately 149:

1.

**Why R=1.** Read requests return immediately from whichever node receives them — the Leader or any
Follower — without contacting additional nodes. This minimizes read latency, which is critical given
that product reads account for roughly 99% of all database operations in our workload.

**Why W=3.** All three nodes must confirm before a write returns success. Since confirmations happen
in parallel, write latency is bounded by the slowest responding node rather than the sum of all
nodes. This is acceptable because product writes are extremely rare — occurring only during the
initial load of 1,000 products and occasional catalog updates. The slower write path does not impact
the system under normal operating conditions.

**Evidence.** The W=3, R=1 configuration delivered the lowest and most consistent read
latency across all configurations tested, with minimal long-tail behavior on the read path. This
directly supports our decision for the Product Service, where fast and predictable reads are the
primary requirement.

**CAP trade-off (CP).** This configuration prioritizes Consistency and Partition Tolerance,
sacrificing Availability. With W=3, every write must be confirmed by all three nodes — if any single
node is unavailable, writes will be blocked. We accept this trade-off because product writes are so
infrequent that write unavailability during a node failure has negligible operational impact.
Meanwhile, R=1 may return a slightly stale value if a Follower has not yet received the latest write
propagation, but given that product descriptions and prices change extremely rarely, a customer
briefly seeing a slightly outdated value has minimal business impact.

### Carts KV — Leaderless, N=3, W=2, R=2

**Read-write ratio (~50 : 50).** The Shopping Cart database has a more balanced read-write ratio.
Each Add-to-cart session contributes one read and one write. Each Checkout session contributes one
read and one write. Gives a read-to-write ratio of approximately 50:50.

**Why W=2, R=2.** Shopping cart data is highly sensitive, losing a customer's cart contents or
double-charging a credit card are serious business errors. Therefore, strong write consistency is
essential. R + W = 4 > N = 3 guarantees that every read will overlap with the most recent write by
at least one node, ensuring strong consistency without requiring all nodes to participate in every
operation.

**Evidence.** Compared to W=5, R=1 in previous testing, W=2, R=2 reduces write latency from
approximately 1,000ms to approximately 400ms, while maintaining the same consistency guarantee. W=2,
R=2 provide a more balanced latency distribution between reads and writes.

**Why Leaderless.** Shopping cart writes are frequent and time sensitive. With Leaderless, any node
can coordinate a write, distributing the write load evenly across all nodes.

**CAP trade-off (CP).** We deprioritize Availability. Requiring W=2 means that if two or more nodes
are simultaneously unavailable, write operations will fail. It is better to return an error to the
customer than to silently lose cart items or commit an incomplete order. Consistency and Partition
Tolerance are prioritized over Availability.

---

## Autoscaling choices

### Autoscaling configuration

We use **ECS Application Auto Scaling** on **`DesiredCount`** with **target tracking** policies:

- **Metrics:** `ECSServiceAverageCPUUtilization` and `ECSServiceAverageMemoryUtilization`.
- **Targets:** about **70%** CPU and **70%** memory for Product and Cart; **CCA** uses a **lower CPU
  target (40%)** so the payment service scales out earlier on CPU (memory is tracked as well).
- **Bounds:** **`min_capacity = 1`**, **`max_capacity = 3`** for scaled services—enough for class
  experiments but **not unlimited**; once all replicas are running, further load increases cause CPU
  to stay high and latency and errors to rise.

When both CPU and memory policies apply to a service, AWS uses the **more demanding** one (not “both
must exceed their targets before scaling”).

The table below is our final **task-size** configuration together with these policies (from the
successful **`round-5`** Locust run):

| service name                   | CPU  | Memory | desired count min capacity | desired count max capacity |
|--------------------------------|------|--------|----------------------------|----------------------------|
| product service                | 4096 | 8192   | 1                          | 3                          |
| shopping cart service          | 4096 | 8192   | 1                          | 3                          |
| credit card authorizer service | 256  | 512    | 1                          | 3                          |
| warehouse service              | 4096 | 8192   | 1                          | 1                          |

### Reasons for these choices

- **Target tracking** is straightforward to explain and behaves predictably for CPU-heavy work (
  including **`SimulatedLoad.busyWait`** in the services).
- **70%** balances **utilization** and **headroom**; **CCA at 40% CPU** reflects that checkout is
  latency-sensitive and we want spare capacity earlier.
- **`max_capacity = 3`** limits cost and matches typical course sandbox limits.
- **Warehouse** is excluded from horizontal scaling to keep **single-writer-style inventory**.

### Simulated load: log-normal distribution

Each HTTP handler in the four services calls *
*`SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs())`** (see **`common`** module, *
*`SimulatedLoad.java`**). The delay is **log-normal** with **`mu = ln(300)`**, **`sigma = 0.8`**,
then **clamped to at most 5 000 ms**—so the **median** is **300 ms**, with a **right-skewed tail** (
roughly **~1.1 s** at P95 and **~2 s** at P99 for the uncapped distribution; rare draws hit the
cap).

**`busyWait`** spins CPU work and periodically allocates small byte arrays until the delay elapses,
so both **CPU and memory** pressure show up in ECS metrics—useful for exercising **target tracking
**.

**Why log-normal?** Latency in real systems is usually **skewed**: many fast requests, a few long
ones. Log-normal matches that shape better than a **uniform** random delay.

**Why these parameters?** **300 ms** median stands in for “typical” business logic; **`sigma = 0.8`
** widens the tail enough to trigger scaling; the **5 s** cap limits pathological waits (similar in
spirit to client timeouts).

### Bottleneck analysis

**Definition of bottleneck**

We identify a bottleneck when a service shows **CPU saturation** beyond its scaling target with no
room to scale further, **response time at least doubling** compared to normal load, or a *
*meaningful rise in error rate** — any one of these is sufficient.

Different load levels exposed different bottlenecks, so we iterated through multiple tuning rounds:

**Request Statistics**

| Type | Name                          | # Requests  Percentage of Total |
|------|-------------------------------|---------------------------------|
| GET  | /products/[productId]         | 82.6%                           |
| POST | /shopping-carts/addItem       | 16.8%                           |
| POST | /shopping-carts/[id]/checkout | 0.6%                            |

#### Product Service Bottleneck

**Configuration**

| service name | cpu  | memory | desired count min capacity | desired count max capacity |
|--------------|------|--------|----------------------------|----------------------------|
| product      | 2048 | 4096   | 1                          | 3                          |
| cart         | 1024 | 2048   | 1                          | 3                          |
| cca          | 256  | 512    | 1                          | 3                          |
| warehouse    | 512  | 1024   | 1                          | 1                          |

![Locust report (after-2)](./locust-load-tester/reports-after-2/screenshot.png)

**CPU utilization**

![CPU utilization after Round 2](./locust-load-tester/reports-after-2/cpu.png)

**Memory utilization**

![Memory utilization after Round 2](./locust-load-tester/reports-after-2/memory.png)

**Bottlenecks**

**Product Service:** **`POST .../addItem`** errors pointed to the **Product** service, not to
downstream services mis-attributed in logs.

#### Warehouse Service Bottleneck

**Configuration**

| service name | cpu  | memory | desired count min capacity | desired count max capacity |
|--------------|------|--------|----------------------------|----------------------------|
| product      | 4096 | 8192   | 1                          | 3                          |
| cart         | 2048 | 4096   | 1                          | 3                          |
| cca          | 512  | 1024   | 1                          | 3                          |
| warehouse    | 2048 | 4096   | 1                          | 1                          |

![Locust report (after-3)](./locust-load-tester/reports-after-3/screenshot.png)

**CPU utilization**

![CPU utilization after Round 3](./locust-load-tester/reports-after-3/cpu.png)

**Memory utilization**

![Memory utilization after Round 3](./locust-load-tester/reports-after-3/memory.png)

**Bottlenecks**

1. **Bottleneck shifted downstream:** After doubling Product to 4096 CPU, **`GET /products`** became
   fast (median 450 ms, ~0 failures), but **`addItem`** failures **doubled** (5 492 → 12 312) and
   changed from HTTP **500** (Product returning errors) to **504** (gateway timeouts). This
   indicates the bottleneck moved from Product itself to the **rest of the `addItem` chain**
   —primarily **Warehouse** (single task at 2048 CPU) and the **Carts KV** write.
2. **Checkout:** **504 timeouts** appeared for the first time (483 failures) on the long critical
   path (Cart → Warehouse → CCA), confirming downstream saturation.

#### Shopping Cart Service Bottleneck

**Configuration**

| service name | cpu  | memory | desired count min capacity | desired count max capacity |
|--------------|------|--------|----------------------------|----------------------------|
| product      | 4096 | 8192   | 1                          | 3                          |
| cart         | 2048 | 4096   | 1                          | 3                          |
| cca          | 256  | 512    | 1                          | 3                          |
| warehouse    | 4096 | 8192   | 1                          | 1                          |

**CCA task size (256 / 512 vs. Round 3’s 512 / 1024):** In Round 3 we gave CCA larger tasks to
reduce checkout latency, but **Container Insights** showed **CCA average CPU remained very low**.
The extra vCPU kept **`ECSServiceAverageCPUUtilization`** below our **40%** target-tracking
threshold, so **CCA rarely scaled out** while **Product** and **Shopping Cart** did. We **reverted
to 256 / 512** so that, for similar checkout load, **utilization relative to provisioned CPU is
higher**, which helps **Application Auto Scaling** add CCA tasks sooner and keeps **scale-out timing
** closer to the other services (still capped at **`max_capacity = 3`**).

![Locust report (after-4)](./locust-load-tester/reports-after-4/screenshot.png)

**Bottleneck**

The **Shopping Cart** public ALB target went **Unhealthy** quickly (health check timeouts under
load). In next Round we **raised the Cart target group health check timeout (5s → 15s)** and *
*increased Cart task CPU and memory**.

![Shopping Cart ALB target health (after-4)](./locust-load-tester/reports-after-4/shopping-cart-alb-timed-out.png)

#### Best Configuration

**Configuration**

**Shopping Cart** public ALB target group health check timeout **5s → 15s**. Final task sizes:

| service name | cpu  | memory | desired count min capacity | desired count max capacity |
|--------------|------|--------|----------------------------|----------------------------|
| product      | 4096 | 8192   | 1                          | 3                          |
| cart         | 4096 | 8192   | 1                          | 3                          |
| cca          | 256  | 512    | 1                          | 3                          |
| warehouse    | 4096 | 8192   | 1                          | 1                          |

![Locust report (after-5)](./locust-load-tester/reports-after-5/screenshot.png)

**CPU utilization (round-5)**

![CPU utilization after Round 5](./locust-load-tester/reports-after-5/cpu.png)

**Memory utilization (round-5)**

![Memory utilization after Round 5](./locust-load-tester/reports-after-5/memory.png)

This Round confirmed the tuned configuration handles **1 500 users** with near-zero failures. The
next step was to push beyond this to find the **overload point** (see Round 6 in the Evidence
section below).

---

## Evidence: scaling behavior and load results

This section has three parts: **(1)** CloudWatch evidence of ECS scale-out on the final run, **(2)**
Locust numbers for overload across tuning rounds, **(3)** why services are **not** scaled
identically.

### ECS auto-scaling (Best Round)

All figures in this subsection are from **Best Round**, in the **same time window** as the Best
Round Locust run.

**Product**

![product scale events](./locust-load-tester/reports-after-5/product-scale-events.png)

**Shopping Cart**

![shopping cart scale events](./locust-load-tester/reports-after-5/cart-scale-events.png)

**CCA**

![cca scale events](./locust-load-tester/reports-after-5/cca-scale-events.png)

**Desired task count**

**Product**, **Shopping Cart**, and **CCA** in **Round 5** typically **scaled out in the same time
window** (curves differ, but they move together under the same load step).

![ECS desired task count — Product, Shopping Cart, CCA](./locust-load-tester/reports-after-5/number-of-desired-task.png)

### Overload condition

We load-tested across six rounds. **Rounds 1–5** iteratively tuned task sizes and autoscaling (see
Bottleneck analysis above). **Round 6** used the final configuration to push past the system's
capacity.

**Round 5 (tuned, up to 1 500 users)** proved the configuration handles normal load well—autoscaling
triggered for all services and failure rate was near zero. **Round 6** used the same configuration
but a **stair-step of 1 500 → 2 500 → 3 500** concurrent users (**300 s per step**, ~15 min total)
to push past the system's capacity.

**Aggregate (all endpoints)**

| Run                         |      Users | Total requests | Failures | Failure rate |
|-----------------------------|-----------:|---------------:|---------:|-------------:|
| Best Round (tuned, ~40 min) |      1 500 |      1,362,961 |        8 |  **0.0006%** |
| Round 6 (overload, ~15 min) | peak 3 500 |        442,525 |      377 |   **0.085%** |

**Per endpoint — Best Round vs Round 6**

| Endpoint             | Round 5 (tuned)                                | Round 6 (overload)                                          |
|----------------------|------------------------------------------------|-------------------------------------------------------------|
| `GET /products/{id}` | 1,126,986 req — **0** fail — median **0.57 s** | 367,112 — **0** fail — median **1 s**                       |
| `POST .../addItem`   | 228,733 — **0** fail — median **3.7 s**        | 73,263 — **174** fail (504) — median **12 s**               |
| `POST .../checkout`  | 7,242 — **8** fail — median **8.4 s**          | 2,150 — **203** fail (201 × 504, 2 × 400) — median **22 s** |

**Round 6 Locust report**

![Locust report Round 6](./locust-load-tester/reports-after-6/screenshot.png)

**Round 6 CPU utilization (all scalable services at or near max capacity)**

![CPU utilization Round 6](./locust-load-tester/reports-after-6/cpu.png)

Under overload, the system shows a **cascading saturation** pattern:

- **Product** (avg ~95%) and **Warehouse** (avg ~99%) are the **compute bottlenecks** — CPU
  frequently hits 100%.
- **Shopping Cart** (avg ~75%) is lower because it is an **orchestrator**: most of its wall-clock
  time is spent waiting for Product and Warehouse to respond (I/O wait does not consume CPU).
- **CCA** (avg ~50%) remains under-utilized because upstream services saturate first — checkout
  requests **timeout before reaching CCA** (cascading failure). CCA is already at the Fargate
  minimum (256 / 512) with a 40% scaling threshold.

Failures are **504 timeouts** on `addItem` and `checkout`, caused by the **entire downstream chain**
being slow, not a single service. This confirms **no single bottleneck** — the system overloads as a
whole.

### Are all systems equally scaled?

**No—and that is intentional.** Configuration in Terraform:

- **Product, Shopping Cart, Credit Card Authorizer:** ECS **Application Auto Scaling** with *
  *`min_capacity = 1`**, **`max_capacity = 3`**, **target tracking** on *
  *`ECSServiceAverageCPUUtilization`** and **`ECSServiceAverageMemoryUtilization`** (CPU target *
  *70%** for Product and Cart; **40%** for CCA; memory target **70%** where configured).
- **Warehouse:** **no** application autoscaling—**desired count is fixed at 1** so inventory stays
  consistent.
- **KV clusters:** run on **EC2** with configurable **N / W / R** and replication mode (
  `leader-follower` vs `leaderless`); scaling is **not** the same mechanism as ECS Fargate task
  autoscaling.
- **Task sizes** differ by service (e.g. larger Product and Warehouse tasks than CCA), so capacity
  is **deliberately asymmetric**.

Even when **desired tasks** rise together (see **Desired task count** above), **Product** often
reached **max tasks (3)** while **Shopping Cart** sometimes **stopped at 2**, because *
*service-level average CPU** on Cart **did not stay above** the threshold long enough for a third
scale-out—consistent with **downstream wait time** rather than Cart CPU alone.

### What we would do with more money

1. **Raise `max_capacity`** beyond 3 for **Product** and **Cart** (and possibly CCA), **or**
   increase **per-task CPU and memory** where metrics show saturation.
2. **Warehouse:** we would not scale out replicas without changing the inventory’s consistency
   model; with more budget we would **increase the single task size** and store the inventory into
   distributed KV databases.
3. **KV:** larger **EC2** instances or **more nodes** with tuned **N/W/R** if latency or failure
   rates justify it.
4. **Observability:** longer retention, alarms on **5xx**, **target health**, and **per-service
   latency** to separate **Product, Warehouse, and KV** quickly during incidents.

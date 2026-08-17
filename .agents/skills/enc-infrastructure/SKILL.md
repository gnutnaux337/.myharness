---
name: enc-infrastructure
description: >
  Expert guidance and architectural standards for developing, configuring, and maintaining background infrastructure,
  workers, and realtime communication services across the ENC ecosystem (enc-infrastructure, enc-admin-worker,
  enc-ship-worker, enc-websocket, enc-ship-websocket).
  Enforces Quartz job scheduling patterns (TriggerFactory validation, virtual threads, PostgreSQL LISTEN/NOTIFY listeners),
  EMQX MQTT pub/sub integration (BaseMqttPublisher/Subscriber), STOMP/WebSocket realtime audio and notification pipelines,
  and multi-datasource R2DBC configuration.

  Use this skill when:
  - Adding or modifying Quartz background jobs in enc-admin-worker or enc-ship-worker
  - Implementing or debugging PostgreSQL LISTEN/NOTIFY runtime reschedule listeners
  - Creating or configuring STOMP/WebSocket controllers, presence listeners, or audio streams in enc-websocket
  - Managing EMQX MQTT pub/sub publishers/subscribers in enc-infrastructure
  - Configuring R2DBC multi-datasource pools or worker virtual thread executors

  ACTIVATE when the user mentions:
  "enc-infrastructure", "enc-admin-worker", "enc-ship-worker", "enc-websocket", "enc-ship-websocket",
  "Quartz", "TriggerFactory", "LISTEN/NOTIFY", "PostgreSQL NOTIFY", "STOMP", "WebSocket",
  "EMQX", "MQTT", "BaseMqttPublisher", "BaseMqttSubscriber", "AudioSocket", "tạo worker job", "thêm background job".
---

# ENC Infrastructure & Workers Engineering Skill

This skill governs the infrastructure, background workers, and real-time streaming modules in the ENC ecosystem:
- **Background Workers**: `enc-admin-worker` (Admin Quartz Worker), `enc-ship-worker` (Shipboard Quartz Worker)
- **Realtime WebSocket Services**: `enc-websocket` (Admin STOMP/WebSocket), `enc-ship-websocket` (Shipboard STOMP/WebSocket)
- **Infrastructure & MQTT**: `enc-infrastructure` (EMQX MQTT pub/sub, Alert Notification Client, Event bus)

---

## 1. Architecture Overview

```
ENC Infrastructure Ecosystem
├── enc-infrastructure       # EMQX MQTT pub/sub (BaseMqttPublisher/Subscriber), notification clients
├── enc-admin-worker         # Quartz background jobs, PG LISTEN/NOTIFY dynamic reschedule, R2DBC multi-DB
├── enc-ship-worker          # Shipboard background jobs (backup, sync, storage cleanup, NMEA ingest)
└── enc-websocket            # STOMP broker, presence tracking, meeting audio PCM stream, alert push
```

---

## 2. Background Workers (`enc-admin-worker` & `enc-ship-worker`)

Workers are **headless Spring Boot processes** (`spring.main.web-application-type: none`) running on **Java 25 virtual threads**. They use **Quartz JDBC Job Store** to execute scheduled tasks.

### 1. The Standard Quartz Job Pattern
Worker jobs run on dedicated worker threads. Unlike WebFlux REST APIs, **Quartz jobs MUST use `.block()` and throw `JobExecutionException`**:

```java
package com.metaforce.enc.admin_worker.scheduler.job;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
@Slf4j
public class DataCleanupJob implements Job {

    private final DataCleanupService cleanupService;

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        log.info("Starting DataCleanupJob execution: {}", context.getJobDetail().getKey());
        try {
            // MUST use .block() — do NOT use .subscribe()
            cleanupService.performCleanup()
                .doOnError(e -> log.error("DataCleanupJob error: {}", e.getMessage(), e))
                .block();
            log.info("DataCleanupJob completed successfully");
        } catch (Exception e) {
            log.error("DataCleanupJob failed: {}", e.getMessage(), e);
            // Throwing JobExecutionException ensures Quartz records failure in qrtz_fired_triggers / audit logs
            throw new JobExecutionException("DataCleanupJob execution failed", e, false);
        }
    }
}
```

> ⚠️ **CRITICAL RULE**: **NEVER use `.subscribe()` in Quartz jobs.**  
> `.subscribe()` causes Quartz to mark the job as finished immediately before the reactive pipeline completes, preventing retry on failure and swallowing error logs.

---

### 2. TriggerFactory & Cron Validation
All triggers **MUST** be built and validated through `TriggerFactory` to prevent high-frequency trigger DoS (blocking sub-second triggers `*` or `*/1`):

```java
// Correct Trigger Creation:
Trigger trigger = triggerFactory.buildTrigger(config.getCronExpression(), "dataCleanupJob", "cleanupGroup");
```

---

### 3. Dynamic Rescheduling via PostgreSQL `LISTEN/NOTIFY`
Workers do not need a restart when job configuration changes in the database. PostgreSQL triggers issue `NOTIFY <channel>`, received by a virtual thread listener:

```
DB UPDATE config ──> PostgreSQL Trigger NOTIFY ──> Virtual Thread Listener ──> SchedulerService.reschedule()
```

#### Listener Pattern (`listener/DataConfigChangeListener.java`):
```java
@Component
@RequiredArgsConstructor
@Slf4j
public class DataConfigChangeListener implements ApplicationRunner {

    private final DataSource dataSource;
    private final DataSchedulerService schedulerService;

    @Override
    public void run(ApplicationArguments args) {
        // Runs in a dedicated virtual thread loop
        Thread.ofVirtual().name("pg-notify-data-config").start(this::listenLoop);
    }

    private void listenLoop() {
        while (!Thread.currentThread().isInterrupted()) {
            try (Connection conn = dataSource.getConnection();
                 Statement stmt = conn.createStatement()) {
                PGConnection pgConn = conn.unwrap(PGConnection.class);
                stmt.execute("LISTEN data_config_changed");

                while (!Thread.currentThread().isInterrupted()) {
                    PGNotification[] notifications = pgConn.getNotifications(5000);
                    if (notifications != null) {
                        for (PGNotification notification : notifications) {
                            log.info("Received notification on channel: {}", notification.getName());
                            schedulerService.reschedule();
                        }
                    }
                }
            } catch (Exception e) {
                log.warn("PostgreSQL LISTEN connection lost, reconnecting in 5s: {}", e.getMessage());
                try {
                    Thread.sleep(5000);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                }
            }
        }
    }
}
```

---

### 4. Scheduler Service Pattern (`scheduler/service/DataSchedulerService.java`)
```java
@Service
@RequiredArgsConstructor
@Slf4j
public class DataSchedulerService implements ApplicationRunner {

    private final Scheduler scheduler;
    private final TriggerFactory triggerFactory;
    private final DataConfigRepository configRepository;

    @Override
    public void run(ApplicationArguments args) {
        reschedule();
    }

    public synchronized void reschedule() {
        try {
            DataConfig config = configRepository.findFirstActive().block();
            JobKey jobKey = JobKey.jobKey("dataCleanupJob", "cleanupGroup");
            TriggerKey triggerKey = TriggerKey.triggerKey("dataCleanupTrigger", "cleanupGroup");

            if (config == null || !Boolean.TRUE.equals(config.getIsEnabled())) {
                scheduler.pauseJob(jobKey);
                log.info("Paused dataCleanupJob because config is disabled or absent");
                return;
            }

            Trigger newTrigger = triggerFactory.buildTrigger(config.getCronExpression(), "dataCleanupTrigger", "cleanupGroup");
            if (scheduler.checkExists(triggerKey)) {
                scheduler.rescheduleJob(triggerKey, newTrigger);
                log.info("Rescheduled dataCleanupJob with new cron: {}", config.getCronExpression());
            } else {
                JobDetail jobDetail = JobBuilder.newJob(DataCleanupJob.class)
                        .withIdentity(jobKey)
                        .storeDurably()
                        .build();
                scheduler.scheduleJob(jobDetail, newTrigger);
                log.info("Scheduled dataCleanupJob with cron: {}", config.getCronExpression());
            }
        } catch (Exception e) {
            log.error("Failed to reschedule dataCleanupJob: {}", e.getMessage(), e);
        }
    }
}
```

---

## 3. Realtime WebSockets (`enc-websocket` & `enc-ship-websocket`)

The WebSocket subsystem provides STOMP messaging, real-time alert broadcasts, user presence detection, and raw WebSocket binary streaming for live audio PCM.

### 1. STOMP Configuration & Interceptors
- **`LangHandshakeInterceptor`**: Extracts `lang` query param / `Accept-Language` during WS handshake and binds to user session attributes.
- **`StompConnectInterceptor`**: Validates JWT bearer token on `STOMP CONNECT` frame and binds authenticated principal.
- **`PresenceSessionListener`**: Listens for `@EventListener SessionConnectedEvent` and `SessionDisconnectEvent` to maintain active online status via `PresenceService`.

### 2. Live Audio Streaming (`MeetingAudioSocketController.java`)
Handles binary PCM chunks for real-time meeting transcription and WebRTC fallback:
- Buffers audio chunks per meeting room.
- Dispatches PCM streams to ASR speech-to-text engines asynchronously.
- Broadcasts generated speech transcript events back to subscribers over STOMP topic `/topic/meeting/{id}/transcript`.

---

## 4. EMQX MQTT & Messaging (`enc-infrastructure`)

### 1. `BaseMqttPublisher`
Publishes typed payloads to EMQX topics with QoS 0/1/2 and automatic reconnection:
```java
@Component
@RequiredArgsConstructor
public class VesselTelemetryPublisher extends BaseMqttPublisher {

    public Mono<Void> publishPosition(String mmsi, PositionPayload payload) {
        String topic = String.format("enc/vessels/%s/position", mmsi);
        return publish(topic, payload, MqttQoS.AT_LEAST_ONCE);
    }
}
```

### 2. `BaseMqttSubscriber`
Subscribes to wildcards (e.g. `enc/vessels/+/telemetry`) and processes reactive streams:
```java
@Component
@RequiredArgsConstructor
@Slf4j
public class SensorTelemetrySubscriber extends BaseMqttSubscriber {

    @Override
    protected String topicFilter() {
        return "enc/vessels/+/telemetry";
    }

    @Override
    protected Mono<Void> handleMessage(String topic, byte[] payload) {
        // Parse and ingest without blocking
        return telemetryIngestService.process(topic, payload);
    }
}
```

---

## 5. Key Infrastructure Rules & Standards

1. **Worker Job Execution**:
   - Always use `.block()` inside Quartz `Job.execute()` methods. Never call `.subscribe()`.
   - Wrap in `try-catch` and throw `JobExecutionException` on failure.
   - Use `flatMap(..., concurrency)` with a conservative limit (e.g. 4) when executing batch deletions/updates to avoid exhausting R2DBC connection pools.

2. **Cron Validation**:
   - Always validate cron strings through `TriggerFactory.buildTrigger()`.
   - Never allow sub-second cron triggers in user-configurable database tables.

3. **PostgreSQL LISTEN/NOTIFY**:
   - Run listeners on virtual threads (`Thread.ofVirtual()`).
   - Use automatic 5s backoff reconnection when database disconnects occur.

4. **WebSocket / STOMP**:
   - Always authenticate incoming frames via `StompConnectInterceptor`.
   - Respect client language preferences via `LangHandshakeInterceptor`.

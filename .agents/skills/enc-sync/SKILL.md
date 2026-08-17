---
name: enc-sync
description: >
  Expert guidance and architectural standards for developing, configuring, and troubleshooting the distributed data
  synchronization engine across the ENC ecosystem (java-sync-common, enc-admin-api, enc-ship-api, enc-admin-worker, enc-ship-worker).
  Enforces @SyncMeta configuration, topological dependency resolution (@SyncTableDependency), UUID reference mapping
  (@SyncReference, @SyncPullReference, @SyncPushReference), large file staging (@SyncAttachmentData), Quartz AutoSyncJob scheduling,
  and reactive conflict resolution.

  Use this skill when:
  - Adding or modifying synchronization support on entities (@SyncMeta, @SyncTableDependency, @SyncReference)
  - Implementing sync data providers, pull persisters, or push receivers
  - Debugging sync cycles, topological sorting order, foreign key resolution, or UUID mapping issues
  - Configuring sync profiles (SyncConfig, SyncMeta, SyncMappingConfig) in enc-admin-api or enc-ship-api
  - Working with AutoSyncJob, SyncSchedulerService, and PostgreSQL LISTEN/NOTIFY in worker services
  - Handling binary attachments sync, chunked transfer, or large sync off-peak windows

  ACTIVATE when the user mentions:
  "enc-sync", "java-sync-common", "@SyncMeta", "@SyncTableDependency", "@SyncReference", "SyncService",
  "SyncDataProvider", "SyncPullPersister", "SyncPushPersister", "AutoSyncJob", "SyncConfig", "SyncMeta",
  "đồng bộ dữ liệu", "cấu hình sync", "thêm entity sync", "lỗi sync", "sync order", "UUID reference".
---

# ENC Distributed Data Synchronization Skill

This skill governs the bidirectional distributed data synchronization framework between Admin (HQ Cloud) and Ship (Edge/Onboard) across the ENC monorepo:
- **Core Sync Engine**: `java-sync-common` (Annotations, Interfaces, Topological Sorting, Reference Resolvers, Persisters)
- **API Nodes**: `enc-admin-api` (Admin Sync Hub, Push Receivers, Profile Resolvers), `enc-ship-api` (Shipboard Sync Client)
- **Workers**: `enc-admin-worker` (HQ AutoSync Jobs), `enc-ship-worker` (Shipboard AutoSync Jobs, Large Data Scheduling)

---

## 1. Architecture Overview

The ENC Sync Engine synchronizes relational PostgreSQL databases over intermittent and constrained satellite/VSAT/4G links without distributed locks:

```
┌──────────────────────────────────────┐            Satellite / VSAT / 4G             ┌──────────────────────────────────────┐
│           Admin Hub (Cloud)          │ ◄──────────────────────────────────────────► │          Ship Client (Edge)          │
├──────────────────────────────────────┤                                              ├──────────────────────────────────────┤
│ • enc-admin-api (PushReceiver)       │         HTTP Delta Payload (JSON/GZIP)       │ • enc-ship-api (SyncClient)          │
│ • enc-admin-worker (AutoSyncJob)     │ ◄──────────────────────────────────────────► │ • enc-ship-worker (AutoSyncJob)      │
│ • java-sync-common                   │         Binary Attachments / Chunks          │ • java-sync-common                   │
└──────────────────────────────────────┘                                              └──────────────────────────────────────┘
```

---

## 2. Entity Sync Declaration & Annotations

Every synchronizable entity must declare `@SyncMeta` and foreign key reference annotations in its domain class:

### 1. The `@SyncMeta` Annotation
```java
package com.metaforce.enc.adminapi.domain.admin;

import com.metaforce.java.sync_common.annotation.*;
import com.metaforce.java.sync_common.enumeration.SyncDirection;
import com.java.common.api.base.BaseEntity;
import lombok.*;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@ToString(callSuper = true)
@Table("vehicle_inspections")
@SyncMeta(
    entityName = "vehicle_inspections",
    syncOrder = 10,
    direction = { SyncDirection.ADMIN_TO_SHIP, SyncDirection.SHIP_TO_ADMIN },
    dependsOn = {
        @SyncTableDependency(target = ShipCombine.class, columnName = "ship_uuid", dependOnColumnName = "uuid")
    },
    syncFrequency = 300,        // Sync every 5 minutes
    isLargeData = false,        // If true, scheduled only during large-sync off-peak windows
    enabled = true
)
public class VehicleInspection extends BaseEntity<Long> {

    @Id
    @Column("id")
    private Long id;

    @Column("uuid")
    private String uuid;

    @Column("name")
    private String name;

    @Column("code")
    private String code;

    // Foreign Key Reference Mapping
    @SyncReference(target = ShipCombine.class, referenceColumn = "uuid")
    @Column("ship_id")
    private Long shipId;

    @Column("ship_uuid")
    private String shipUuid;

    // Binary Attachment Mapping (e.g. Photos / Scanned PDFs)
    @SyncAttachmentData(storageDirectory = "inspections")
    @Column("attachment_file_id")
    private Long attachmentFileId;
}
```

---

### 2. Synchronization Annotations Reference

| Annotation | Location | Purpose |
|---|---|---|
| `@SyncMeta` | Class | Registers the entity in `sync_meta` registry. Configures direction, order, and dependencies. |
| `@SyncTableDependency` | `@SyncMeta(dependsOn = ...)` | Enforces topological ordering: the target table will always sync before this table. |
| `@SyncReference` | Field | Bidirectional reference mapper. Replaces local integer ID with global UUID during transmission and resolves it back on receipt. |
| `@SyncPullReference` | Field | Unidirectional reference mapping used when pulling records from Admin to Ship. |
| `@SyncPushReference` | Field | Unidirectional reference mapping used when pushing records from Ship to Admin. |
| `@IgnoreSyncReference` | Field | Ignores FK resolution during payload serialization. |
| `@SyncAttachmentData` | Field | Marks file/binary references for staging and chunked transport. |
| `@SearchSync` | Class | Marks entities searchable against HT06 external system; enables `_cache=true` on-demand ingestion. |

---

## 3. HT06 External Search & `@SearchSync` (`SearchEntity`)

HT06 is an external authority system providing live query data for vessels, voyages, persons, violations, etc., to `enc-admin-api`.

### 1. The `@SearchSync` & `SearchEntity` Pattern
Entities that can be queried from HT06 extend `SearchEntity<ID>` (which provides the `@Column("cached") private Boolean cached;` field) and are marked with `@SearchSync`:

```java
@Getter
@Setter
@Table("ship_combine")
@SearchSync // Indicates entity can be searched on HT06 and cached locally
@SyncMeta(...)
public class ShipCombine extends SearchEntity<Long> {
    // fields...
}
```

### 2. The `cached` Flag & `_cache=true` Mechanism
- **Periodic Sync (`cached = false`)**: Records inserted or updated by the normal sync engine (`AbstractPullPersister` / `AbstractDefaultSyncPushReceiver`) are marked with `cached = false` (authoritative internal sync data).
- **HT06 External Search (`cached = true`)**: When searching via `ExternalSearchService` with `_cache=true` (or default cache mode), results retrieved live from HT06 are automatically inserted into the local table with `cached = true`.
- **Conflict & Update**: If a record already exists locally when queried from HT06, existing fields are merged and the authoritative status is preserved.

---

## 4. The Synchronization Lifecycle

```
1. Topological Sort  ──>  2. Query Deltas  ──>  3. Reference Encoding  ──>  4. Transmission  ──>  5. UUID Resolve & Upsert
   (DAG of Tables)        (last_sync_time)       (FK ID -> UUID)          (HTTP GZIP)            (SyncPull/PushPersister)
```

### 1. Delta Resolution (`SyncDataProvider`)
- Queries modified rows where `modified_at > :lastSyncTime` or `is_delete = 1`.
- Serializes rows into typed transfer DTOs with global `uuid` identifiers.

### 2. UUID & Reference Resolution (`SyncPullPersister` / `SyncPushPersister`)
- Local integer database IDs (`id`) are never shared directly across environments.
- Foreign keys are converted to foreign `uuid`s before transmission.
- The receiving node queries its local database using `uuid` to find the corresponding local integer `id`. If the parent does not exist yet, the topological DAG order guarantees it was sent in the preceding batch.

### 3. Conflict Resolution Strategy
- **Timestamp Last-Write-Wins**: `modified_at|updated_at` is compared to resolve concurrent edits.
- **Soft Deletes (`is_delete`)**: Propagated across nodes. Deleting on one node marks `is_delete = 1` on the receiving node.

---

## 4. Background Workers & AutoSyncJob (`enc-admin-worker` & `enc-ship-worker`)

Background sync is scheduled via Quartz using `AutoSyncJob`:

### 1. Scheduling Modes
1. **Global Default AutoSync**:
   - Runs for all active `SyncMeta` records where `sync_frequency IS NULL`.
   - Uses the cron expression configured in `sync_config`.
2. **Custom Frequency AutoSync**:
   - Runs for specific `SyncMeta` groups having custom `sync_frequency` intervals (e.g. high-priority vessel position vs low-priority legal documents).
3. **Large Sync Off-Peak Window**:
   - Entities marked with `isLargeData = true` are filtered out during regular hours.
   - Synchronized only when current time falls within `largeSyncStart` - `largeSyncEnd` (e.g. `00:00 - 05:00`).

### 2. Quartz Worker Execution Pattern
```java
// Quartz Job executes reactively with mandatory .block() and retry policy
syncMetaRepository.findAllByOrderBySyncOrderAsc()
    .filter(meta -> Boolean.TRUE.equals(meta.getEnabled()))
    .collectList()
    .flatMap(metas -> syncService.triggerSync(new LinkedHashSet<>(metas), configId))
    .retryWhen(Retry.fixedDelay(2, Duration.ofSeconds(10)))
    .block();
```

---

## 5. Key Rules & Troubleshooting

1. **Topological Order (`syncOrder` & `dependsOn`)**:
   - Always declare `@SyncTableDependency` if table A has a foreign key referencing table B.
   - Never introduce circular dependencies between synced entities.

2. **UUID Integrity**:
   - Every synchronizable table **MUST** have a `uuid VARCHAR(64)` column with a unique index.
   - New entities must automatically assign `UUID.randomUUID().toString()` on creation.

3. **Transaction Isolation**:
   - Ingest payloads within `EntityTransactionManager` to ensure batch atomicity.
   - Always log sync execution history to `sync_log` and `sync_file_log`.

4. **Off-Peak Large Data Discipline**:
   - Heavy tables (e.g. chart cells, radar tracks, multi-megabyte media) **MUST** set `isLargeData = true` in `@SyncMeta`.

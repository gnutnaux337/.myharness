---
name: enc-backend
description: >
  Expert guidance and architectural standards for developing Java Spring WebFlux reactive backend services
  across the ENC monorepo (enc-admin-api, enc-ship-api, enc-app-api, enc-share-api, java-api-common, java-database-common).
  Enforces standard CRUD patterns with BaseRouter, BaseHandler, BaseCrudService, BaseQueryService, GenericQueryBuilder,
  relation base query (@Relation, RelationQueryService), custom non-CRUD functional endpoints, and backend i18n management.

  Use this skill when:
  - Creating or modifying backend APIs in enc-admin-api, enc-ship-api, enc-app-api, or enc-share-api
  - Implementing CRUD entities: Domain Entity, Request/Response DTO, Criteria, Repository, QueryBuilder, Mapper, QueryService, ServiceImpl, Handler, Router
  - Implementing custom non-CRUD endpoints (override customRoutes, custom Handler/Service methods, reactive WebClient/R2DBC)
  - Managing entity relations and 1-N child hydration with @Relation and RelationQueryService
  - Handling backend i18n, validation messages, and properties files (MessageResource, resources/entity/*.properties)
  - Working with R2DBC multi-datasource, audit logging (@AuditField), and permission generation (@AutoPermission)

  ACTIVATE when the user mentions:
  "enc-backend", "enc-admin-api", "enc-ship-api", "BaseRouter", "BaseHandler", "BaseAdminHandler",
  "BaseCrudService", "BaseQueryService", "GenericQueryBuilder", "@Relation", "RelationQueryService",
  "MessageResource", "tạo API mới", "thêm entity backend", "thêm endpoint", "custom routes", "backend i18n".
---

# ENC Backend Engineering Skill

This skill governs the development of all reactive backend modules in the ENC ecosystem:
- **WebFlux APIs**: `enc-admin-api` (Admin API), `enc-ship-api` (Shipboard API), `enc-app-api` (Desktop Sync API), `enc-share-api` (External Interop API)
- **Shared Libraries**: `java-api-common` (BaseRouter, BaseHandler, BaseCrudService, BaseQueryService, @Relation engine), `java-database-common` (R2DBC data layer, Flyway, multi-tenancy), `java-sync-common` / `enc-api-common` (DTO contracts)

---

## 1. Architecture Overview & Core Patterns

The backend is built on **Spring Boot 3.x + Spring WebFlux + R2DBC + PostgreSQL**. All endpoints use **Functional Endpoints** (`RouterFunction<ServerResponse>`) and non-blocking reactive chains (`Mono`/`Flux`).

Backend API development divides strictly into two cases:
1. **Case 1: Standard CRUD Entity API** (BaseRouter + BaseAdminHandler + BaseQueryService + BaseCrudService + GenericQueryBuilder + @Relation)
2. **Case 2: Custom / Non-CRUD Functional Endpoints & Domain APIs** (`customRoutes()`, custom Handler/Service reactive methods, transactions)

---

## 2. Case 1: Standard CRUD Entity API Checklist

Every standard entity requires 11 coordinated artifacts:

```
Domain Entity  ──>  DTO (Req/Res)  ──>  Criteria  ──>  Repository + QueryBuilder  ──>  Mapper
      │
      └──>  QueryService  ──>  CrudService  ──>  Handler (BaseAdminHandler)  ──>  Router (BaseRouter)
                  │
                  └──>  i18n Properties (resources/entity/*.properties)
```

### 1. Domain Entity (`domain/admin/{Entity}.java`)
```java
package com.metaforce.enc.adminapi.domain.admin;

import com.java.common.api.annotation.AuditField;
import com.java.common.api.annotation.AutoPermission;
import com.java.common.api.annotation.UniqueCode;
import com.java.common.api.base.BaseEntity;
import com.java.common.api.datasource.DataSourceType;
import com.java.common.api.datasource.UseDataSource;
import com.java.common.api.enumeration.AuditFieldType;
import lombok.*;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@ToString(callSuper = true)
@UseDataSource(DataSourceType.ADMIN)
@Table("vehicle_inspections")
@AutoPermission // Auto-generates CRUD permissions in RBAC
// Note: If entity supports external search on HT06 (insert on search with _cache=true),
// extend SearchEntity<Long> (from com.metaforce.java.sync_common.domain.SearchEntity) and add @SearchSync
public class VehicleInspection extends BaseEntity<Long> {

    @Id
    @Column("id")
    private Long id;

    @Column("name")
    private String name;

    @UniqueCode
    @Column("code")
    private String code;

    @AuditField(fieldType = AuditFieldType.ENTITY_REF, repository = ShipRepository.class, key = "Ship", displayFields = "name")
    @Column("ship_id")
    private Long shipId;

    @AuditField(fieldType = AuditFieldType.ENUM, enumClass = InspectionStatus.class)
    @Column("status")
    private Integer status;

    @AuditField(fieldType = AuditFieldType.BOOLEAN)
    @Column("is_active")
    private Short isActive;
}
```

### 2. Request DTO & Response DTO
**Request DTO** (`dto/request/VehicleInspectionRequestDTO.java`):
```java
package com.metaforce.enc.adminapi.dto.request;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.java.common.api.annotation.FieldMessageEntity;
import com.java.common.api.annotation.Relation;
import com.java.common.api.enumeration.FetchMode;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.util.List;

@Data
@FieldMessageEntity // Binds field names to i18n property keys for validation
public class VehicleInspectionRequestDTO {

    @JsonProperty("name")
    @NotBlank
    private String name;

    @JsonProperty("code")
    @NotBlank
    private String code;

    @JsonProperty("ship_id")
    @NotNull
    private Long shipId;

    @JsonProperty("status")
    private Integer status;

    @JsonProperty("is_active")
    private Short isActive;

    // Optional 1-N relation child list from request body:
    @Relation(repository = VehicleInspectionItemRepository.class, joinColumn = "inspectionId", fetchMode = FetchMode.SINGLE_ONLY)
    @JsonProperty("items")
    private List<VehicleInspectionItemRequestDTO> items;
}
```

**Response DTO** (`dto/response/VehicleInspectionResponseDTO.java`):
```java
package com.metaforce.enc.adminapi.dto.response;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.java.common.api.annotation.Relation;
import com.java.common.api.dto.response.BaseEntityDTO;
import com.java.common.api.enumeration.FetchMode;
import lombok.*;
import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
@EqualsAndHashCode(callSuper = true)
public class VehicleInspectionResponseDTO extends BaseEntityDTO {

    @JsonProperty("id")
    private Long id;

    @JsonProperty("name")
    private String name;

    @JsonProperty("code")
    private String code;

    @JsonProperty("ship_id")
    private Long shipId;

    @JsonProperty("ship_name")
    private String shipName; // Join projection field

    @JsonProperty("status")
    private Integer status;

    @JsonProperty("is_active")
    private Short isActive;

    // 1-N Relation: Auto-hydrated by RelationQueryService on GET /{id} or GET /{id}/{relation}
    @Relation(repository = VehicleInspectionItemRepository.class, joinColumn = "inspectionId", fetchMode = FetchMode.SINGLE_ONLY)
    @JsonProperty("items")
    private List<VehicleInspectionItemResponseDTO> items;
}
```

### 3. Criteria (`criteria/VehicleInspectionCriteria.java`)
```java
package com.metaforce.enc.adminapi.criteria;

import com.java.common.api.annotation.QueryFilter;
import com.java.common.api.criteria.BaseCriteria;
import lombok.Data;
import lombok.EqualsAndHashCode;

@Data
@EqualsAndHashCode(callSuper = true)
public class VehicleInspectionCriteria extends BaseCriteria {

    @QueryFilter(isSearchable = true)
    private String name;

    @QueryFilter(isSearchable = true)
    private String code;

    private Long shipId;

    private Integer status;

    private Short isActive;
}
```

### 4. Repository & QueryBuilder (**MANDATORY**)
**Repository** (`repository/admin/VehicleInspectionRepository.java`):
```java
package com.metaforce.enc.adminapi.repository.admin;

import com.java.common.api.repository.BaseRepository;
import com.metaforce.enc.adminapi.criteria.VehicleInspectionCriteria;
import com.metaforce.enc.adminapi.domain.admin.VehicleInspection;

public interface VehicleInspectionRepository extends BaseRepository<VehicleInspection, Long, VehicleInspectionCriteria> {
    // Custom SQL queries if needed:
    // @Query("SELECT * FROM vehicle_inspections WHERE code = :code AND is_delete = 0")
    // Mono<VehicleInspection> findByCode(String code);
}
```

**QueryBuilder** (`repository/admin/query/VehicleInspectionQueryBuilder.java`):
> ⚠️ **CRITICAL**: Every `BaseRepository` MUST have a matching `GenericQueryBuilder<Criteria>` in the `query` subpackage. Missing this causes runtime `queryFactory is null`.
```java
package com.metaforce.enc.adminapi.repository.admin.query;

import com.java.common.api.repository.GenericQueryBuilder;
import com.metaforce.enc.adminapi.criteria.VehicleInspectionCriteria;

public class VehicleInspectionQueryBuilder extends GenericQueryBuilder<VehicleInspectionCriteria> {
    // GenericQueryBuilder automatically builds filters from @QueryFilter in Criteria.
    // Override forSearch(...) or forCount(...) only if custom SQL JOINs are needed.
}
```

### 5. Mapper (`service/mapper/VehicleInspectionMapper.java`)
```java
package com.metaforce.enc.adminapi.service.mapper;

import com.java.common.api.service.BaseMapper;
import com.metaforce.enc.adminapi.domain.admin.VehicleInspection;
import com.metaforce.enc.adminapi.dto.request.VehicleInspectionRequestDTO;
import com.metaforce.enc.adminapi.dto.response.VehicleInspectionResponseDTO;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface VehicleInspectionMapper extends BaseMapper<VehicleInspection, VehicleInspectionResponseDTO, VehicleInspectionRequestDTO> {
}
```

### 6. QueryService (`service/query/VehicleInspectionQueryService.java`)
```java
package com.metaforce.enc.adminapi.service.query;

import com.java.common.api.enumeration.PaginationPolicy;
import com.java.common.api.exception.component.MessageResource;
import com.java.common.api.service.BaseQueryService;
import com.metaforce.enc.adminapi.criteria.VehicleInspectionCriteria;
import com.metaforce.enc.adminapi.domain.admin.VehicleInspection;
import com.metaforce.enc.adminapi.dto.request.VehicleInspectionRequestDTO;
import com.metaforce.enc.adminapi.dto.response.VehicleInspectionResponseDTO;
import com.metaforce.enc.adminapi.repository.admin.VehicleInspectionRepository;
import com.metaforce.enc.adminapi.service.mapper.VehicleInspectionMapper;
import org.springframework.stereotype.Service;

@Service
public class VehicleInspectionQueryService extends BaseQueryService<VehicleInspectionResponseDTO, VehicleInspectionCriteria, VehicleInspection, Long, VehicleInspectionRequestDTO> {

    protected VehicleInspectionQueryService(VehicleInspectionRepository repo, VehicleInspectionMapper mapper, MessageResource msg) {
        super(repo, mapper, msg);
    }

    @Override
    public PaginationPolicy getPaginationPolicy() {
        return PaginationPolicy.STANDARD; // STANDARD for regular CRUD, CATALOG for name-sorted catalogs
    }
}
```

### 7. Service Interface & Impl (`service/VehicleInspectionService.java` & `service/Impl/VehicleInspectionServiceImpl.java`)
```java
package com.metaforce.enc.adminapi.service;

import com.java.common.api.service.CustomCrudService;
import com.metaforce.enc.adminapi.dto.request.VehicleInspectionRequestDTO;
import com.metaforce.enc.adminapi.dto.response.VehicleInspectionResponseDTO;
import reactor.core.publisher.Mono;

public interface VehicleInspectionService extends CustomCrudService<VehicleInspectionResponseDTO, VehicleInspectionRequestDTO, Long> {
    Mono<Void> approve(Long id);
}
```

**ServiceImpl** (`service/Impl/VehicleInspectionServiceImpl.java`):
```java
package com.metaforce.enc.adminapi.service.Impl;

import com.java.common.api.datasource.EntityTransactionManager;
import com.java.common.api.exception.component.MessageResource;
import com.java.common.api.exception.exception.CommonException;
import com.java.common.api.service.BaseCrudService;
import com.java.common.api.service.IBaseAuditService;
import com.metaforce.enc.adminapi.criteria.VehicleInspectionCriteria;
import com.metaforce.enc.adminapi.domain.admin.VehicleInspection;
import com.metaforce.enc.adminapi.dto.request.VehicleInspectionRequestDTO;
import com.metaforce.enc.adminapi.dto.response.VehicleInspectionResponseDTO;
import com.metaforce.enc.adminapi.repository.admin.VehicleInspectionItemRepository;
import com.metaforce.enc.adminapi.repository.admin.VehicleInspectionRepository;
import com.metaforce.enc.adminapi.service.VehicleInspectionService;
import com.metaforce.enc.adminapi.service.mapper.VehicleInspectionMapper;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class VehicleInspectionServiceImpl
        extends BaseCrudService<VehicleInspectionResponseDTO, VehicleInspectionRequestDTO, VehicleInspection, Long, VehicleInspectionCriteria>
        implements VehicleInspectionService {

    private final VehicleInspectionItemRepository itemRepository;

    protected VehicleInspectionServiceImpl(
            VehicleInspectionRepository repo,
            VehicleInspectionMapper mapper,
            IBaseAuditService auditService,
            MessageResource messageResource,
            EntityTransactionManager tx,
            VehicleInspectionItemRepository itemRepository) {
        super(repo, mapper, auditService, messageResource, tx);
        this.itemRepository = itemRepository;
    }

    @Override
    protected Mono<Void> validateSave(VehicleInspectionRequestDTO dto) {
        return repository.existsByColumn("code", dto.getCode())
            .flatMap(exists -> exists
                ? messageResource.getMessage("code_already_exists")
                    .flatMap(msg -> Mono.error(new CommonException(msg)))
                : Mono.empty());
    }

    // Lifecycle hook: Save 1-N child items after entity creation
    @Override
    protected Mono<VehicleInspection> afterCreate(VehicleInspection entity, VehicleInspectionRequestDTO request) {
        if (request.getItems() == null || request.getItems().isEmpty()) {
            return Mono.just(entity);
        }
        return saveChildItems(entity.getId(), request.getItems()).thenReturn(entity);
    }

    // Lifecycle hook: Soft-delete old items and re-save on update
    @Override
    protected Mono<VehicleInspection> afterUpdate(VehicleInspection entity, VehicleInspectionRequestDTO request) {
        if (request.getItems() == null) {
            return Mono.just(entity);
        }
        return itemRepository.softDeleteByColumn("inspection_id", entity.getId())
                .then(saveChildItems(entity.getId(), request.getItems()))
                .thenReturn(entity);
    }

    // Lifecycle hook: Cascade soft-delete child items before entity deletion
    @Override
    protected Mono<VehicleInspection> beforeDelete(VehicleInspection entity, VehicleInspectionRequestDTO request) {
        return itemRepository.softDeleteByColumn("inspection_id", entity.getId()).thenReturn(entity);
    }

    private Mono<Void> saveChildItems(Long inspectionId, List<VehicleInspectionItemRequestDTO> items) {
        // Pure reactive batch insert
        return Flux.fromIterable(items)
                .map(dto -> toChildEntity(inspectionId, dto))
                .collectList()
                .flatMap(itemRepository::saveAll)
                .then();
    }

    @Override
    public Mono<Void> approve(Long id) {
        return repository.findById(id)
            .switchIfEmpty(Mono.defer(() -> Mono.error(new CommonException("Not found"))))
            .flatMap(entity -> {
                entity.setStatus(2); // Approved
                return repository.save(entity);
            })
            .then();
    }
}
```

### 8. Handler (`handler/VehicleInspectionHandler.java`)
> **Always extend `BaseAdminHandler` in `enc-admin-api`** (or `BaseHandler` in other microservices):
```java
package com.metaforce.enc.adminapi.handler;

import com.java.common.api.util.ValidationUtil;
import com.metaforce.enc.adminapi.criteria.VehicleInspectionCriteria;
import com.metaforce.enc.adminapi.domain.admin.VehicleInspection;
import com.metaforce.enc.adminapi.dto.request.VehicleInspectionRequestDTO;
import com.metaforce.enc.adminapi.dto.response.VehicleInspectionResponseDTO;
import com.metaforce.enc.adminapi.service.VehicleInspectionService;
import com.metaforce.enc.adminapi.service.query.VehicleInspectionQueryService;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

@Component
public class VehicleInspectionHandler extends BaseAdminHandler<
        VehicleInspectionResponseDTO,
        VehicleInspectionCriteria,
        VehicleInspectionResponseDTO,
        VehicleInspectionRequestDTO,
        VehicleInspection,
        Long> {

    private final VehicleInspectionService vehicleInspectionService;

    protected VehicleInspectionHandler(
            ValidationUtil validationUtil,
            VehicleInspectionQueryService queryService,
            VehicleInspectionService crudService) {
        super(validationUtil);
        this.queryService = queryService;
        this.crudService = crudService;
        this.vehicleInspectionService = crudService;
    }

    @Override
    protected Long parseId(String id) {
        return Long.valueOf(id);
    }

    // Custom non-CRUD handler method:
    public Mono<ServerResponse> approve(ServerRequest request) {
        Long id = parseId(request.pathVariable("id"));
        return vehicleInspectionService.approve(id)
                .then(ServerResponse.ok().bodyValue(Map.of("success", true)));
    }
}
```

### 9. Router (`router/VehicleInspectionRouter.java`)
```java
package com.metaforce.enc.adminapi.router;

import com.java.common.api.base.BaseRouter;
import com.metaforce.enc.adminapi.handler.VehicleInspectionHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;
import static org.springframework.web.reactive.function.server.RequestPredicates.POST;
import static org.springframework.web.reactive.function.server.RouterFunctions.route;

@Configuration
public class VehicleInspectionRouter extends BaseRouter<VehicleInspectionHandler> {

    private final VehicleInspectionHandler handler;

    public VehicleInspectionRouter(VehicleInspectionHandler handler) {
        this.handler = handler;
    }

    @Override
    protected String basePath() {
        return "api/v1/vehicle-inspections";
    }

    @Override
    protected VehicleInspectionHandler handler() {
        return handler;
    }

    @Bean
    public RouterFunction<ServerResponse> vehicleInspectionRoutes() {
        return routes(); // Generates: GET /, GET /{id}, POST /, PUT /{id}, DELETE /{id}, DELETE /delete-all/{ids}, GET /{id}/audit-log, GET /{id}/{relation}
    }

    // Override customRoutes to register extra non-CRUD endpoints under the same resource:
    @Override
    protected RouterFunction<ServerResponse> customRoutes() {
        return route(POST(basePath() + ID + "/approve"), handler::approve);
    }
}
```

---

## 3. Case 2: Custom / Non-CRUD Functional APIs

For complex domain logic, report generation, external gateways, batch tasks, or WebSocket/SSE feeds:

### 1. Standalone Router Configuration
```java
package com.metaforce.enc.adminapi.router;

import com.metaforce.enc.adminapi.handler.CustomReportHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;
import static org.springframework.web.reactive.function.server.RequestPredicates.*;
import static org.springframework.web.reactive.function.server.RouterFunctions.route;

@Configuration
public class CustomReportRouter {

    @Bean
    public RouterFunction<ServerResponse> customReportRoutes(CustomReportHandler handler) {
        return route(POST("api/v1/reports/custom/generate"), handler::generateReport)
            .andRoute(GET("api/v1/reports/custom/stream"), handler::streamProgress);
    }
}
```

### 2. Standalone Handler with Reactive Pipeline
```java
@Component
@RequiredArgsConstructor
@Slf4j
public class CustomReportHandler {

    private final CustomReportService reportService;
    private final ValidationUtil validationUtil;

    public Mono<ServerResponse> generateReport(ServerRequest request) {
        return request.bodyToMono(ReportRequestDTO.class)
                .flatMap(validationUtil::validate)
                .flatMap(reportService::processReport)
                .flatMap(result -> ServerResponse.ok().bodyValue(result));
    }

    public Mono<ServerResponse> streamProgress(ServerRequest request) {
        return ServerResponse.ok()
                .contentType(MediaType.TEXT_EVENT_STREAM)
                .body(reportService.getProgressFlux(), ProgressEvent.class);
    }
}
```

---

## 4. Relations and Hydration: `@Relation` & `RelationQueryService`

`java-api-common` provides automatic 1-N relation fetching:
- **`@Relation`**: Declared on List fields in Request/Response DTOs:
  - `repository`: Repository class implementing `IRelationRepository` / `BaseRepository`
  - `joinColumn`: Foreign key field name (e.g. `"inspectionId"`)
  - `fetchMode`:
    - `FetchMode.SINGLE_ONLY`: Fetched only on single record queries (e.g. `GET /api/v1/.../{id}`)
    - `FetchMode.ALWAYS`: Fetched in both list and detail queries
- **Dedicated Relation Endpoint**: `BaseRouter` automatically exposes:
  `GET /api/v1/{entity}/{id}/{relation}?search=...&page=0&size=20`
  Handled by `RelationQueryService.findRelationPaged(...)`.

---

## 5. Backend i18n Management

The backend localization is driven by Spring `MessageSource` and `MessageResource` reading `resources/entity/*.properties` files:

### 1. File Location & Naming Convention
- Path: `src/main/resources/entity/`
- Pattern: `{entity}_vi.properties` and `{entity}_en.properties` (or `{camelCaseEntity}_{vi,en}.properties`)

### 2. Standard Property Keys
```properties
# resources/entity/vehicle_inspection_vi.properties
name=Kiểm định phương tiện
title.create=Thêm mới kiểm định
title.update=Cập nhật kiểm định
title.detail=Chi tiết kiểm định

attribute.name=Tên kiểm định
attribute.code=Mã kiểm định
attribute.ship_id=Tàu kiểm định
attribute.status=Trạng thái
attribute.is_active=Trạng thái hoạt động

placeholder.name=Nhập tên kiểm định...
placeholder.code=Nhập mã kiểm định...

add_success=Thêm mới kiểm định thành công
update_success=Cập nhật kiểm định thành công
delete_success=Xóa kiểm định thành công
code_already_exists=Mã kiểm định đã tồn tại trên hệ thống
```

### 3. Accessing Translations in Code
Inject `MessageResource` and call reactive helper:
```java
// Reactive translation lookup matching client's Accept-Language:
messageResource.getMessage("code_already_exists")
    .flatMap(msg -> Mono.error(new CommonException(msg)));

// With positional format arguments:
messageResource.getMessage("item_not_found_with_id", id)
    .flatMap(msg -> Mono.error(new NotFoundException(msg)));
```

---

## 6. Key Rules & Coding Standards for Backend

1. **Pure Reactive Streams**:
   - Never call `.block()` or `.subscribe()` inside WebFlux API flows.
   - Use `Mono.defer()` for lazy exception instantiation (`switchIfEmpty(Mono.defer(() -> ...))`).
   - Use `Mono.zip()` for parallel async lookups.
   - Use `flatMap()` for asynchronous transformations, `map()` only for synchronous value mapping.

2. **Transaction Management**:
   - Use `EntityTransactionManager` / `TransactionalOperator` for multi-table updates.
   - Do NOT rely on imperative `@Transactional` with blocking behavior.

3. **Multi-Datasource Awareness**:
   - Always declare `@UseDataSource(DataSourceType.ADMIN)` (or `LOG`, `POSITION`) on domain entities.

4. **Audit Logging & Security**:
   - Annotate foreign keys, enums, and booleans with `@AuditField`.
   - Never expose raw SQL errors or sensitive database topology to clients.

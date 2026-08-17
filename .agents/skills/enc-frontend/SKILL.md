---
name: enc-frontend
description: >
  Expert guidance and workflow standard for developing frontend features across the ENC monorepo
  (enc-admin-app, enc-ship-app, enc-app, enc-app-common, enc-map-common, react-app-common, react-chat-common, react-map-common).
  Enforces convention-over-configuration CRUD patterns (BaseListPage, entityConfigRegistry, FormBuilder/DetailBuilder),
  standardized service/hook layers (BaseService, BaseHook, TanStack Query), modular i18n management, and shared component reuse.

  Use this skill when:
  - Adding a new entity/CRUD feature to enc-admin-app, enc-ship-app, or enc-app
  - Creating or updating columns, filters, sorts, cards, forms, details, tabs, or models in src/configs/
  - Implementing or modifying services (BaseService, callApi) and hooks (BaseHook, TanStack Query mutations)
  - Adding i18n translation keys in src/lang/{vi,en}/
  - Integrating shared components, map features (@enc/map-common), or chat features (react-chat-common)
  - Refactoring or developing common components in react-app-common and enc-app-common

  ACTIVATE when the user mentions:
  "enc-frontend", "enc-admin-app", "enc-ship-app", "enc-app", "enc-app-common", "react-app-common",
  "BaseListPage", "BaseService", "BaseHook", "entity config", "FormBuilder", "DetailBuilder",
  "tạo view mới", "thêm màn hình", "thêm entity", "thêm filter", "thêm column", "i18n frontend".
---

# ENC Frontend Engineering Skill

This skill governs the development of all frontend modules and shared packages in the ENC ecosystem:
- **Applications**: `enc-admin-app` (Admin Portal), `enc-ship-app` (Shipboard Client), `enc-app` (Desktop/Tauri Communication Client)
- **Shared Libraries**: `react-app-common` (Core UI/CRUD Engine), `enc-app-common` (Maritime Domain Layer), `enc-map-common` / `react-map-common` (Geospatial & Map Engine), `react-chat-common` (Realtime Communication Engine)

---

## 1. Architecture Overview & Monorepo Structure

The ENC frontend ecosystem follows a **Convention-over-Configuration** architecture centered around `BaseListPage` and Vite glob registry auto-resolution:

```
ENC Frontend Monorepo
├── react-app-common          # Core engine: BaseListPage, FormBuilder, DetailBuilder, registries, generic hooks & utils
├── enc-app-common            # Domain layer: Maritime constants, ship/person models, CameraViewer, CccdSearchPanel
├── enc-map-common            # Geospatial engine: MapOverview, S-57 ENC layers, vessel renderers, STOMP zone alerts
├── react-chat-common         # Chat engine: ConversationView, ChatBox, WebRTC/Socket hooks, multimedia messaging
└── Applications (enc-admin-app, enc-ship-app, enc-app)
    ├── src/configs/          # Entity list definitions (columns, filters, sorts, forms, details, tabs, models)
    ├── src/services/         # API clients extending BaseService with callApi
    ├── src/hooks/            # Query & Mutation hooks generated with BaseHook + TanStack Query
    ├── src/views/            # Screen views (BaseListPage wrappers or custom layouts)
    ├── src/lang/             # i18n JSON files per domain (vi, en)
    └── src/auth/             # callApi instance, token storage, refresh rotation, 401 handling
```

---

## 2. Standard Workflow: Adding a New Feature / Entity

When adding a new entity (e.g. `vehicle_inspection` or `harbor_fee`):

```
1. Create Service  ───>  2. Create Hook  ───>  3. Create i18n (vi/en)  ───>  4. Create Configs  ───>  5. Create View & Route
  (BaseService)            (BaseHook)              (JSON files)                 (columns/filters...)      (BaseListPage)
```

### Step 1: Create Service (`src/services/{PascalCase}Service.ts`)
Must export a singleton instance extending `BaseService` with endpoint prefix `v1/...`:

```typescript
import callApi from '@auth/callApi';
import { BaseService } from '@enc/app-common';

export interface VehicleInspection {
  id?: number;
  ship_id: number;
  inspection_date: string;
  status: string;
  notes?: string;
}

class VehicleInspectionService extends BaseService {
  // Add custom non-CRUD endpoints here if needed:
  approve = (id: number) =>
    this.callApi({
      url: `${this.endpoint}/${id}/approve`,
      method: 'POST',
    });
}

export const vehicleInspectionService = new VehicleInspectionService('v1/vehicle-inspections', callApi);
```

### Step 2: Create Hook (`src/hooks/{PascalCase}Hook.ts`)
Must use `BaseHook` to generate standard React Query hooks (`useGetList`, `useGetDetail`, `useInsert`, `useUpdate`, `useDelete`), and define custom mutations with `queryClient.invalidateQueries`:

```typescript
import { vehicleInspectionService } from '@services/VehicleInspectionService';
import { BaseHook } from '@enc/app-common';
import { useMutation, useQueryClient } from '@tanstack/react-query';

export const {
  useGetList,
  useGetDetail,
  useInsert,
  useUpdate,
  useDelete,
  useDeleteMultiple,
} = BaseHook('VehicleInspections', vehicleInspectionService);

const LIST_KEY = ['vehicle_inspection'];

export const useApproveInspection = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => vehicleInspectionService.approve(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: LIST_KEY }),
  });
};
```

### Step 3: Handle i18n Translations
Every new entity requires dedicated translation files:
1. Create `src/lang/vi/{entity_snake_case}.json`:
```json
{
  "vehicle_inspection": "Kiểm định phương tiện",
  "ship_id": "Tàu",
  "inspection_date": "Ngày kiểm định",
  "status": "Trạng thái",
  "notes": "Ghi chú"
}
```
2. Create `src/lang/en/{entity_snake_case}.json`:
```json
{
  "vehicle_inspection": "Vehicle Inspection",
  "ship_id": "Ship",
  "inspection_date": "Inspection Date",
  "status": "Status",
  "notes": "Notes"
}
```
3. Register the JSON in `src/lang/vi/index.js` and `src/lang/en/index.js`:
```javascript
import vehicle_inspection from './vehicle_inspection.json';

export default {
  ...otherModules,
  vehicle_inspection,
};
```

### Step 4: Create Entity Configs in `src/configs/`
Use `snake_case` filename matching the entity name.

#### Columns:
- **Entity Column Config (for `BaseListPage`)** (`src/configs/columns/{entity}.tsx`):
  Use `ColumnDef` from `@enc/app-common`:
  ```typescript
  import { type ColumnDef } from '@enc/app-common';
  import dayjs from 'dayjs';

  const vehicleInspectionColumns: ColumnDef[] = [
    { dataIndex: 'ship_name' },
    {
      dataIndex: 'inspection_date',
      dataType: 'date',
      render: (v: any) => formatDateTime(v, 'date'),
      renderText: (v: any) => formatDateTime(v, 'date'),
    },
    { dataIndex: 'status' },
    { dataIndex: 'created_at', dataType: 'date' },
  ];

  export default vehicleInspectionColumns;
  ```

- **Non-Entity / Custom Table Columns (not using `BaseListPage`)**:
  Use `ColumnType` from `antd/es/table` directly (do **NOT** use `ColumnDef`), and always use icon buttons in the action column:
  ```typescript
  import type { ColumnType } from 'antd/es/table';
  import { Button, Tooltip, Space } from 'antd';
  import { EditOutlined, DeleteOutlined } from '@ant-design/icons';

  export interface CustomItemRecord {
    id: number;
    title: string;
    action_type: string;
  }

  export const customColumns = (
    onEdit: (record: CustomItemRecord) => void,
    onDelete: (record: CustomItemRecord) => void,
  ): ColumnType<CustomItemRecord>[] => [
    {
      title: 'Tiêu đề',
      dataIndex: 'title',
      key: 'title',
    },
    {
      title: 'Hành động',
      dataIndex: 'action_type',
      key: 'action_type',
    },
    {
      title: 'Thao tác',
      key: 'actions',
      width: 100,
      align: 'center',
      render: (_, record) => (
        <Space size="small">
          <Tooltip title="Chỉnh sửa">
            <Button
              type="text"
              size="small"
              icon={<EditOutlined />}
              onClick={() => onEdit(record)}
            />
          </Tooltip>
          <Tooltip title="Xoá">
            <Button
              type="text"
              size="small"
              danger
              icon={<DeleteOutlined />}
              onClick={() => onDelete(record)}
            />
          </Tooltip>
        </Space>
      ),
    },
  ];
  ```

#### Filters (`src/configs/filters/{entity}.tsx`):
```typescript
import { type FilterDef } from '@enc/app-common';

const vehicleInspectionFilters: FilterDef[] = [
  { dataIndex: 'ship_id', type: 'select', isAsync: true, asyncUrl: 'v1/ships' },
  { dataIndex: 'status', type: 'select', options: [/*...*/] },
  { dataIndex: 'inspection_date', type: 'date-range' },
];

export default vehicleInspectionFilters;
```

#### Forms & Details (Optional or Custom):
- **Auto Form/Detail**: Add `src/configs/forms/{entity}.tsx` and `src/configs/details/{entity}.tsx` for `FormBuilder` / `DetailBuilder`.
- **Custom Form/Detail**: Place top-level entry in `src/views/{PascalCase}/components/Form.tsx` and `Detail.tsx`.
- **Tabs**: Add `src/configs/tabs/{entity}.tsx` to define tabs and sub-relations.

### Step 5: Create View & Navigation
Create `src/views/{PascalCase}/index.tsx`:
```typescript
import { BaseListPage } from '@enc/app-common';

const VehicleInspectionView = () => <BaseListPage entity="vehicle_inspection" />;

export default VehicleInspectionView;
```
Register route in `src/routes/` and sidebar menu in navigation configuration with permission checks (`usePermission`, `canViewEntity('vehicle_inspection')`).

---

## 3. Predeclared Utilities & Shared Packages

### `react-app-common` (`@react-app/common`)
- **Components**: `BaseListPage`, `FormBuilder`, `DetailBuilder`, `TabbedDetail`, `RelationTab`, `FormStagingTabs`, `AuditLogTab`, `MiniCalendar`, custom Ant Design wrappers (`Select`, `DatePicker`, `InputNumber`, etc.).
- **Hooks**: `useCrud`, `useAsyncOptions`, `useFilterRenderer`, `usePermission`, `useSidebarMenu`, `useExcelExport`, `useExcelImport`.
- **Utils**: `snakeToCamel`, `camelToSnake`, `formatNumberVi`, `buildSortItems`, `parseSortKey`, `createFetchPage`, `parseJsonLike`.

### `enc-app-common` (`@enc/app-common`)
- **DateTime & Formatting**:
  - `formatDateTime(value, 'datetime' | 'date' | 'time')`: Formats to `"HH:mm DD/MM/YYYY"`, `"DD/MM/YYYY"`, or `"HH:mm:ss"`. **Always prefer this over ad-hoc `dayjs` calls.**
  - `formatNumber(value, decimalPlaces)`: Formats numbers safely with optional decimal precision.
  - `formatFileSize(bytes)`: Converts raw bytes to human-readable string (`B`, `KB`, `MB`).
- **Maritime Utilities**: `getShipTypeIcon`, `getShipColor`, `formatDMS`, `parseCoordinates`, `convertSpeedKnots`.
- **Domain Components**: `PersonCard`, `CccdSearchPanel`, `PersonStagingTab`, `ShipTypeCascaderField`, `CountrySelect`, `CameraViewer` (with WebRTC / PTZ / Object Tracking).
- **Constants & Types**: `shipType`, `shipCombine`, `shipMember`, `shipOwner`, `voyage`, `mission`, `flag`.

### `enc-admin-app/src/utils`
- `MeetingAsrProcessor.ts`: Web Audio API chunking, PCM downsampling, and realtime speech-to-text pipeline.
- `waveformDraw.ts`: Canvas-based real-time audio waveform and frequency visualizer.
- `formulaValidator.ts`: Rule engine mathematical syntax, operators, and variable expression validator.
- `canvas.ts`: Image canvas transformations, scaling, and annotation drawing.
- `vmsDisconnectSummary.ts`, `wrongZoneSummary.ts`, `boundaryCrossingSummary.ts`: Domain metrics aggregation for alert dashboards.
- `ruleEngineResponse.ts`: Formatter and serializer for rule simulation outputs.
- `platform.ts`: Runtime detection of Tauri desktop vs browser web mode.

### `enc-ship-app/src/utils`
- `date.ts`: `formatDateTime` (ISO string for APIs), `defaultStartEnd`, `formatRelativeTime` ("12s trước", "5m trước").
- `cccd.ts`: QR code parsing for Vietnamese citizen identity cards, checksum & field extractors.
- `imo.ts` & `mmsi.ts`: Maritime IMO and MMSI number checksum algorithms and standard formatting.
- `parseNmeaLine.ts`: NMEA 0183 GPS/AIS sentence parser ($GPGGA, $GPRMC, $AIVDM).
- `alertSound.ts` & `zoneAlertSound.ts`: Web Audio API tone synthesis for collision warnings, zone breaches, and SOS alarms.
- `filePreview.ts` & `reportFilePreview.ts`: Blob URL generator, PDF viewer handlers, safe object cleanup.
- `password.ts`, `passwordChangeRequest.ts`, `passwordSnooze.ts`: Password complexity validation and expiration snooze policies.
- `violationMapUtils.ts` & `zoneViolationHistory.ts`: Spatial violation trajectory reconstruction and layer drawing.
- `platform.ts`: Shipboard Tauri vs browser environment detector.

### `enc-map-common` (`@enc/map-common`)
- **Map Components & Controls**: `MapOverview`, S-57 / S-63 ENC layer controls, vessel filters (`AdvancedVesselFilter`), dynamic heading and trail renderer.
- **Geospatial Utils & Symbology**: MIL-STD-2525 SIDC icons, dynamic ship zone polygon conversions, tile offline caching (`useMapTileCache`), STOMP zone alerts (`useStompNotification`).

### `react-chat-common`
- **Chat UI**: `ConversationView`, `ChatBox`, `ChatMessageList`, `ChatInput`, `ChatEditor`, `LocationMessage`, `PersonMessage`, `SosMessage`.
- **Chat Hooks**: `useChatSocket`, `useRealtimeMessage`, `useMessagePagination`, `useMessageSender`, `usePresenceSocket`.

---

## 4. Key Rules & Coding Standards

1. **Naming Standards**:
   - Entities: `snake_case` (e.g. `ship_combine`, `backup_config`, `command_order`)
   - Services: `PascalCaseService.ts` (e.g. `ShipCombineService.ts`)
   - Hooks: `PascalCaseHook.ts` (e.g. `ShipCombineHook.ts`)
   - Config files: `snake_case.tsx` inside `src/configs/{columns,filters,cards,sorts,forms,details,tabs}/`
   - Views: `PascalCase/index.tsx` inside `src/views/`
   - Custom Form/Detail components: `src/views/{PascalCase}/components/Form.tsx` & `Detail.tsx`

2. **Network & Service Layer**:
   - Never use raw `fetch` or `axios` in views or components.
   - Always route calls through `BaseService` or custom service methods powered by `callApi`.
   - In React Query mutations, always invalidate the entity list query key on success to keep UI synchronised.

3. **Translations (i18n)**:
   - Never hardcode user-facing strings in JSX.
   - Colocate entity translations in `src/lang/{vi,en}/{entity}.json` and register them in `index.js`.

4. **Table Columns Definition**:
   - For entity configurations consumed by `BaseListPage`, use `ColumnDef` from `@enc/app-common`.
   - For non-entity / custom tables or views not using `BaseListPage`, use `import type { ColumnType } from 'antd/es/table'` directly instead of `ColumnDef`.

5. **DateTime & Formatting Standardization**:
   - Use `formatDateTime(val, 'datetime' | 'date' | 'time')` from `@enc/app-common` (or app utils) instead of writing ad-hoc `dayjs(val).format(...)` across views and columns.
   - Use `formatNumberVi` or `formatNumber` for currency, coordinates, and quantity displays.

6. **Code Documentation for Complex Logic**:
   - **Mandatory comments**: Add clear, explanatory comments (JSDoc / inline) for any complex or non-obvious logic, including:
     - NMEA/serial parsing and bitmask operations
     - Audio chunking / Web Audio API tone synthesis / ASR processing
     - Canvas drawing, image transformations, and coordinate re-projections
     - Custom validation formulas and regex parsers
     - Complex cache invalidations and optimistic state updates

7. **Table UI Standards**:
   - **Size**: Always use `size="small"` for all tables (custom `<Table size="small" ... />` or `BaseListPage`).
   - **Borders**: Always enable borders (`bordered={true}` / `bordered`).
   - **Action Column**: Always use compact icon buttons (`<Button type="text" size="small" icon={<... />} />` wrapped in `<Tooltip />`) for actions (Edit, Delete, View, Download) in table action columns rather than text buttons or full labeled buttons.

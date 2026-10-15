# Dataverse request patterns

Base URL: `<ENV_URL>/api/data/v9.2/`. Standard headers (the `Dataverse.psm1` asset sets them):

```
Authorization: Bearer <token>
OData-MaxVersion: 4.0
OData-Version: 4.0
Accept: application/json
Content-Type: application/json; charset=utf-8
Prefer: odata.include-annotations="*", odata.maxpagesize=5000
```

Token (client credentials): `POST https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token` with form fields `grant_type=client_credentials`, `client_id`, `client_secret`, `scope=<ENV_URL>/.default`. In GitHub Actions with OIDC, exchange the GitHub ID token instead (`client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer`, `client_assertion=<github token>`).

## Contents
1. Querying and paging
2. Bulk updates
3. Metadata / data dictionary
4. Users and security roles
5. Flows and plug-in steps on/off
6. Audit and telemetry
7. Dependencies
8. Custom API (definition by code)
9. Custom connectors
10. PCF micro-frontends
11. Service protection limits

## 1. Querying and paging

```
GET accounts?$select=accountid,name,statecode&$filter=statecode eq 0 and createdon lt 2024-01-01T00:00:00Z
```
Follow `@odata.nextLink` until absent. Do not build `$skip` (unsupported). For a count: `GET accounts/$count` (max 5,000 reported) or `?$count=true`. For aggregates or complex joins use FetchXML: `GET accounts?fetchXml=<url-encoded fetch>`.

## 2. Bulk updates

Preferred: `UpdateMultiple` (one request per batch, all-or-nothing per batch on standard tables).
```
POST accounts/Microsoft.Dynamics.CRM.UpdateMultiple
{ "Targets": [ { "@odata.type": "Microsoft.Dynamics.CRM.account", "accountid": "<GUID>", "statecode": 1, "statuscode": 2 } ] }
```
- Start at 100–1,000 records per call; make it a parameter (default 200).
- Not every standard table supports it. Check first:
  `GET sdkmessagefilters?$select=sdkmessagefilterid&$filter=primaryobjecttypecode eq '<logicalname>' and sdkmessageid/name eq 'UpdateMultiple'` → one row means supported.
- Fallback when unsupported: per-record `PATCH accounts(<GUID>)` with header `If-Match: *` (prevents accidental upsert-create), or `$batch` with up to 1,000 operations.
- Send only the columns that change. Snapshot their current values first for undo.
- Optional header `MSCRM.BypassCustomPluginExecution: true` (needs the `prvBypassCustomPlugins` privilege). Only use it when the user explicitly wants plug-ins skipped, and say so in the runbook.

## 3. Metadata / data dictionary

```
GET EntityDefinitions?$select=LogicalName,SchemaName,EntitySetName,DisplayName,Description,IsCustomEntity,PrimaryIdAttribute,PrimaryNameAttribute&$filter=IsCustomEntity eq true
GET EntityDefinitions(LogicalName='account')/Attributes?$select=LogicalName,SchemaName,AttributeType,AttributeTypeName,RequiredLevel,DisplayName,Description,IsCustomAttribute
GET EntityDefinitions(LogicalName='account')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?$select=LogicalName&$expand=OptionSet($select=Options)
GET EntityDefinitions(LogicalName='account')?$select=LogicalName&$expand=ManyToOneRelationships($select=SchemaName,ReferencedEntity,ReferencingAttribute)
```
Labels come back as `DisplayName.UserLocalizedLabel.Label` (can be null). Restrict to a solution's tables via `solutioncomponents?$filter=_solutionid_value eq <GUID> and componenttype eq 1` (objectid = MetadataId).

## 4. Users and security roles

- Find user: `GET systemusers?$select=systemuserid,domainname,azureactivedirectoryobjectid,isdisabled,_businessunitid_value&$filter=domainname eq '<UPN>'`
- Roles are **per business unit**. Resolve the role in the user's BU: `GET roles?$select=roleid,name&$filter=name eq '<Role Name>' and _businessunitid_value eq <BU GUID>`
- Assign: `POST systemusers(<USER>)/systemuserroles_association/$ref` body `{ "@odata.id": "<ENV_URL>/api/data/v9.2/roles(<ROLE>)" }`
- Remove: `DELETE systemusers(<USER>)/systemuserroles_association(<ROLE>)/$ref`
- Current roles: `GET systemusers(<USER>)?$select=fullname&$expand=systemuserroles_association($select=name,roleid)`
- Teams: `POST teams(<TEAM>)/teammembership_association/$ref`. For Entra group sync prefer Microsoft Entra group teams (membershiptype) over scripting membership.
- CLI alternative: `pac admin assign-user --environment <url> --user <upn> --role "<name>"`.
- Users must exist in Dataverse first (sync from Entra happens on first access or via `pac admin` / admin center "Add user").

## 5. Flows and plug-in steps on/off

Cloud flows are rows in `workflows` with `category eq 5`. Classic workflows are category 0.
```
GET workflows?$select=workflowid,name,statecode,statuscode,_ownerid_value&$filter=category eq 5
PATCH workflows(<ID>)  { "statecode": 1, "statuscode": 2 }   # turn on
PATCH workflows(<ID>)  { "statecode": 0, "statuscode": 1 }   # turn off
```
Turning a flow on can fail if its connection references have no valid connection, or the caller lacks rights on the flow. Report those per flow rather than aborting the whole run. Scope by solution: `GET solutioncomponents?$filter=_solutionid_value eq <GUID> and componenttype eq 29`.

Plug-in steps: `sdkmessageprocessingsteps`, on `{ "statecode": 0, "statuscode": 1 }`, off `{ "statecode": 1, "statuscode": 2 }`. Filter out Microsoft steps with `ishidden/Value eq false and customizationlevel eq 1`.

## 6. Audit and telemetry

- `GET audits?$select=createdon,operation,action,objecttypecode,_userid_value,_objectid_value&$filter=createdon ge <ISO>&$orderby=createdon desc`
- Async jobs and failures: `asyncoperations?$filter=statuscode eq 31` (Failed).
- Flow run history is not in Dataverse by default; `flowruns` table exists where flow run history in Dataverse is enabled. Otherwise use the Power Automate management connector / admin API.
- For long-term telemetry, recommend the environment's Application Insights export (admin center → Data export) rather than polling.

## 7. Dependencies

- `GET RetrieveDependenciesForUninstall(SolutionUniqueName='<name>')`
- `GET RetrieveMissingDependencies(SolutionUniqueName='<name>')`
- Component types in results are numeric (1 table, 2 column, 26 view, 29 workflow/flow, 60 form, 61 web resource, 80 model app, 300 canvas app, 371 connector, 380 environment variable definition, 10xxx are org-specific). Map them to names in the output.

## 8. Custom API (definition by code)

Create the definition through the Web API inside the solution, then export the solution so the definition lands in source control. Hand-writing the unpacked XML is error-prone.
```
POST customapis
MSCRM.SolutionUniqueName: <SOLUTION>
{
  "uniquename": "<prefix>_BulkDeactivate",
  "name": "<prefix>_BulkDeactivate",
  "displayname": "Bulk Deactivate",
  "description": "...",
  "bindingtype": 0,
  "isfunction": false,
  "isprivate": false,
  "allowedcustomprocessingsteptype": 0,
  "PluginTypeId@odata.bind": "/plugintypes(<GUID>)",
  "CustomAPIRequestParameters": [
    { "uniquename": "TableName", "name": "<prefix>_BulkDeactivate.TableName", "displayname": "Table name", "type": 10, "isoptional": false }
  ],
  "CustomAPIResponseProperties": [
    { "uniquename": "UpdatedCount", "name": "<prefix>_BulkDeactivate.UpdatedCount", "displayname": "Updated count", "type": 7 }
  ]
}
```
`type`: 0 Boolean, 1 DateTime, 2 Decimal, 3 Entity, 4 EntityCollection, 5 EntityReference, 6 Float, 7 Integer, 8 Money, 9 Picklist, 10 String, 11 StringArray, 12 Guid. `bindingtype`: 0 Global, 1 Entity, 2 EntityCollection. `allowedcustomprocessingsteptype`: 0 None, 1 Async only, 2 Sync and async. Set `executeprivilegename` to restrict who can call it. Call it as `POST <prefix>_BulkDeactivate` (global, `isfunction: false`). The plug-in implementing it is a .NET class registered via `pac plugin init` / Plugin Registration.

## 9. Custom connectors

Files per connector (in `modules/<module>/connector/`):
- `apiDefinition.swagger.json`: OpenAPI **2.0**, include `x-ms-summary` and `description` on every parameter so makers see friendly labels, and `x-ms-visibility` (`important|advanced|internal`).
- `apiProperties.json`: `properties.connectionParameters` (e.g. `oauth2` with `identityProvider: "aad"` or `api_key`), `iconBrandColor`, optional `scriptOperations`, `policyTemplateInstances`.
- `icon.png` (optional), `script.csx` (optional C# code).
Deploy: `pac connector create --api-definition-file ... --api-properties-file ... --solution-unique-name <SOLUTION> --environment <url>`; update with `pac connector update --connector-id <id> ...`. Once in a solution, it travels via normal solution export/import.

## 10. PCF micro-frontends

```
pac pcf init --namespace <Ns> --name <Control> --template field --framework react --run-npm-install
npm run build
mkdir solution && cd solution
pac solution init --publisher-name <Publisher> --publisher-prefix <prefix>
pac solution add-reference --path ..
dotnet build -c Release     # produces bin/Release/solution.zip (managed if SolutionPackageType=Managed in the .cdsproj)
```
`ControlManifest.Input.xml` declares `<control namespace control-type="standard|virtual">`, `<property>` entries (`of-type`, `usage="bound|input"`), `<resources>`, and optional `<feature-usage><uses-feature name="WebAPI" required="true"/></feature-usage>`.

## 11. Service protection limits

Per user, per 5 minutes: 6,000 requests, 20 minutes combined execution time, 52 concurrent requests. On HTTP 429 read `Retry-After` (seconds) and wait. Scripts should retry 429/503/502 with backoff (5 attempts) and keep concurrency modest (≤ 8 parallel calls). The asset module implements this.

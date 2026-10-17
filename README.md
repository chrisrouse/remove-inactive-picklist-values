# Remove Inactive Picklist Values

Two Flow actions that remove inactive picklist values when you clone a record.

A restricted picklist rejects inactive values on insert, and values that aren't available for the new record's record type are rejected too. A flow that copies a record from a Get Records element fails if the source record still holds one of those values. Pass the value (or the whole record) through one of these actions first and use the output on the clone.

Both actions work for any object and field, support single and multi-select picklists, and are bulk safe.

## Actions

### Remove Inactive Picklist Values - Single Field

Cleans one picklist or multi-select picklist value.

| Input | Required | Description |
|---|---|---|
| Object API Name | Yes | e.g. `Case`. |
| Field API Name | Yes | e.g. `Status` |
| Current Value | No | The value to clean. For a multi-select picklist, the semicolon-delimited string |
| Record Type Id | No | Also removes values not available for this record type |

Output: **Active Value**. The remaining values, in their original order, or null if none remain.

<img width="507" height="577" alt="Screenshot 2026-10-17 at 9 47 02 AM" src="https://github.com/user-attachments/assets/1f9a87ee-8ae8-46ac-9ab0-9a1076e3c9ed" />


### Remove Inactive Picklist Values - All Fields

Cleans every restricted picklist and multi-select picklist on a record in one step.

| Input | Required | Description |
|---|---|---|
| Record | Yes | The record to clean, e.g. the output of Get Records |
| Record Type Id | No | Filters to this record type's values instead of the record's own `RecordTypeId` |
| Field API Names | No | Only clean these fields. Blank cleans every restricted picklist on the record |

Outputs:
- **Cleaned Record**: a copy of the record with the values removed. The input record is not modified.
- **Changes**: one entry per field that was changed (field, original value, cleaned value).

Notes:
- Only fields retrieved on the record are cleaned. In Get Records, retrieve the picklist fields you want cleaned and `RecordTypeId`.
- Unrestricted picklists are left alone, because they accept any value on insert.

## Record types

Without a Record Type Id, only inactive values are removed. With one, values that aren't available for that record type are removed too. If the clone gets a different record type than the source, pass the **new** record type's Id.

<img width="502" height="770" alt="Screenshot 2026-10-17 at 9 43 19 AM" src="https://github.com/user-attachments/assets/961be3a5-c1e2-4b1a-a89f-704978424a61" />


## Install

This is a 2GP unlocked package with no namespace (version 1.0.1).

- [Install in production or Developer Edition](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tbm000000qE5JAAU)
- [Install in a sandbox](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tbm000000qE5JAAU)

Or with the CLI: `sf package install -p 04tbm000000qE5JAAU -o <org> --wait 20`

Users who run the flow need access to the Apex classes `RemoveInactiveValuesSingleField` and `RemoveInactiveValuesAllFields`, either by profile at install time or through a permission set you assign.

## Installation Troubleshooting

If the installation fails, it is likely due to an issue compiling Apex in your org. Expand the **Advanced Options** section and select *Compile only the Apex in the package*.

<img width="904" height="172" alt="Screenshot 2026-10-17 at 9 35 17 AM" src="https://github.com/user-attachments/assets/cfe4cf83-affc-4c3f-b715-ff98ede14a8e" />


## Development

```
sf project deploy start -d force-app -o <org>
sf apex run test -n RemoveInactiveValuesSingleFieldTest -n RemoveInactiveValuesAllFieldsTest -o <org> -r human -c -w 10
```

The tests use `Account.Industry` and `Contact.LeadSource`, which exist in every org, so they need at least two active `Account.Industry` values.

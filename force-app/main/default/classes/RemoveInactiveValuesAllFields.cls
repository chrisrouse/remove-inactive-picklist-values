/**
 * @description Invocable action that cleans every picklist and multi-select picklist on a record, restricted or
 * not, so the record can be inserted, e.g. when cloning. Values that are inactive (and, when the record has a
 * RecordTypeId, unavailable for its record type) are removed. Uses the lookups in RemoveInactiveValuesSingleField.
 *
 * Only fields retrieved on the record are cleaned, and Field API Names can narrow that further. In Get Records,
 * retrieve the picklist fields you want cleaned and RecordTypeId; without RecordTypeId only inactive values are removed. To filter for a record type
 * other than the record's own (e.g. the clone gets a different one), set Record Type Id on the action.
 *
 * Usage in Flow: add the "Remove Inactive Picklist Values - All Fields" action with Record = {!Get_Original_Case}, then
 * (Manually assign variables) store Cleaned Record in a Case record variable and use it, or its individual
 * fields, on the clone.
 */
public with sharing class RemoveInactiveValuesAllFields {
    private static final Set<Schema.DisplayType> PICKLIST_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.MULTIPICKLIST
    };

    private static Map<String, Map<String, Schema.SObjectField>> fieldsByObject = new Map<String, Map<String, Schema.SObjectField>>();

    /**
     * @description Flow entry point
     * @param requests One request per record to clean
     * @return One result per request, in the same order
     */
    @InvocableMethod(
        label='Remove Inactive Picklist Values - All Fields'
        description='Returns a copy of the record with inactive values removed from all of its picklist fields.'
        category='Picklists'
    )
    public static List<Result> sanitize(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request request : requests) {
            results.add(sanitizeRecord(request));
        }
        return results;
    }

    private static Result sanitizeRecord(Request request) {
        Result result = new Result();
        result.changes = new List<FieldChange>();
        if (request.record == null) {
            return result;
        }

        // Deep copy so the Get Records variable is left untouched
        SObject cleanedRecord = request.record.clone(true, true, true, true);
        String objectName = String.valueOf(cleanedRecord.getSObjectType());
        Map<String, Object> populatedFields = cleanedRecord.getPopulatedFieldsAsMap();
        String recordTypeId = String.isNotBlank(request.recordTypeId) ? request.recordTypeId : getRecordTypeId(populatedFields);
        Set<String> onlyFields = toLowerCaseSet(request.fieldApiNames);

        for (String fieldName : populatedFields.keySet()) {
            if (!onlyFields.isEmpty() && !onlyFields.contains(fieldName.toLowerCase())) {
                continue;
            }
            if (!isPicklist(objectName, fieldName) || populatedFields.get(fieldName) == null) {
                continue;
            }

            String originalValue = String.valueOf(populatedFields.get(fieldName));
            String cleanedValue = RemoveInactiveValuesSingleField.removeDisallowedValues(
                originalValue,
                getAllowedValues(objectName, fieldName, recordTypeId)
            );
            if (cleanedValue != originalValue) {
                cleanedRecord.put(fieldName, cleanedValue);
                result.changes.add(new FieldChange(fieldName, originalValue, cleanedValue));
            }
        }

        result.cleanedRecord = cleanedRecord;
        return result;
    }

    private static String getRecordTypeId(Map<String, Object> populatedFields) {
        return populatedFields.get('RecordTypeId') == null ? null : String.valueOf(populatedFields.get('RecordTypeId'));
    }

    private static Boolean isPicklist(String objectName, String fieldName) {
        if (!fieldsByObject.containsKey(objectName)) {
            fieldsByObject.put(objectName, Schema.describeSObjects(new List<String>{ objectName })[0].fields.getMap());
        }

        Schema.SObjectField field = fieldsByObject.get(objectName).get(fieldName);
        if (field == null) {
            return false; // e.g. a parent relationship on the record
        }
        return PICKLIST_TYPES.contains(field.getDescribe().getType());
    }

    // The record type lookup can lack a field (e.g. one the UI API doesn't expose); describe still works then
    private static Set<String> getAllowedValues(String objectName, String fieldName, String recordTypeId) {
        if (String.isBlank(recordTypeId)) {
            return RemoveInactiveValuesSingleField.getAllowedValues(objectName, fieldName, null);
        }

        try {
            return RemoveInactiveValuesSingleField.getAllowedValues(objectName, fieldName, recordTypeId);
        } catch (RemoveInactiveValuesSingleField.InvalidInputException e) {
            return RemoveInactiveValuesSingleField.getAllowedValues(objectName, fieldName, null);
        }
    }

    private static Set<String> toLowerCaseSet(List<String> values) {
        Set<String> lowerCased = new Set<String>();
        for (String value : values == null ? new List<String>() : values) {
            if (value != null) {
                lowerCased.add(value.toLowerCase());
            }
        }
        return lowerCased;
    }

    /**
     * @description Flow input
     */
    public class Request {
        @InvocableVariable(label='Record' description='The record to clean, e.g. {!Get_Original_Case}' required=true)
        public SObject record;

        @InvocableVariable(
            label='Record Type Id'
            description='Optional. Filters to the values available for this record type instead of the record\'s own RecordTypeId. Use when the clone gets a different record type'
        )
        public String recordTypeId;

        @InvocableVariable(label='Field API Names' description='Optional. Only clean these fields. Blank cleans every picklist retrieved on the record. Unrestricted picklists lose any value that is not active in the picklist, so limit this to the fields you want cleaned')
        public List<String> fieldApiNames;
    }

    /**
     * @description Flow output
     */
    public class Result {
        @InvocableVariable(label='Cleaned Record' description='Copy of the record with disallowed picklist values removed')
        public SObject cleanedRecord;

        @InvocableVariable(label='Changes' description='One entry per field that was changed')
        public List<FieldChange> changes;
    }

    /**
     * @description A field whose value was changed by the cleanup
     */
    public class FieldChange {
        @AuraEnabled
        public String fieldApiName;
        @AuraEnabled
        public String originalValue;
        @AuraEnabled
        public String cleanedValue;

        public FieldChange(String fieldApiName, String originalValue, String cleanedValue) {
            this.fieldApiName = fieldApiName;
            this.originalValue = originalValue;
            this.cleanedValue = cleanedValue;
        }
    }
}

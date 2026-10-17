/**
 * @description Invocable action that removes inactive (and optionally record-type-unavailable) values from a
 * picklist or multi-select picklist value. Works for any object and field. Intended for flows that clone
 * records: a restricted picklist rejects inactive values on insert, so pass the source value through
 * this action first and use the output on the clone.
 *
 * Usage in Flow: add the "Remove Inactive Picklist Values - Single Field" action, then set
 *   Object API Name = Case
 *   Field API Name  = Status
 *   Current Value   = {!Get_Original_Case.Status}
 *   Record Type Id  = {!Get_Original_Case.RecordTypeId}  (optional)
 * and assign the action's Active Value output to the clone.
 *
 * To clean every picklist on a record in one step, see RemoveInactiveValuesAllFields, which reuses the
 * public helpers below.
 */
public with sharing class RemoveInactiveValuesSingleField {
    private static final String MULTI_SELECT_DELIMITER = ';';

    private static Map<String, Set<String>> activeValuesByField = new Map<String, Set<String>>();

    // Keyed by object.recordTypeId, then lowercase field name. Tests seed this because ConnectApi
    // can't be called from a data-siloed test.
    @TestVisible
    private static Map<String, Map<String, Set<String>>> valuesByRecordType = new Map<String, Map<String, Set<String>>>();

    // Tests inject a stub because ConnectApi can't be called from a data-siloed test. Null means call ConnectApi.
    @TestVisible
    private static PicklistValuesSource picklistValuesSource;

    /**
     * @description Flow entry point. Bulk safe: each request is processed independently and lookups
     * are cached per object/field (and per object/record type).
     * @param requests One request per value to filter
     * @return One result per request, in the same order
     */
    @InvocableMethod(
        label='Remove Inactive Picklist Values - Single Field'
        description='Returns the given picklist or multi-select picklist value with any inactive values removed.'
        category='Picklists'
    )
    public static List<Result> filterInactiveValues(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request request : requests) {
            Result result = new Result();
            if (String.isNotBlank(request.currentValue)) {
                Set<String> allowedValues = getAllowedValues(request.objectApiName, request.fieldApiName, request.recordTypeId);
                result.activeValue = removeDisallowedValues(request.currentValue, allowedValues);
            }
            results.add(result);
        }
        return results;
    }

    /**
     * @description Gets the values a picklist field accepts. Without a record type this is every active value
     * (describe). With one, it is the values available for that record type (ConnectApi), which also
     * excludes inactive values.
     * @param objectApiName e.g. Case
     * @param fieldApiName e.g. Status
     * @param recordTypeId Optional record type Id
     * @return The allowed values
     */
    public static Set<String> getAllowedValues(String objectApiName, String fieldApiName, String recordTypeId) {
        if (String.isNotBlank(recordTypeId)) {
            return getRecordTypeValues(objectApiName, fieldApiName, recordTypeId);
        }

        String cacheKey = (objectApiName + '.' + fieldApiName).toLowerCase();
        if (activeValuesByField.containsKey(cacheKey)) {
            return activeValuesByField.get(cacheKey);
        }

        Schema.DescribeSObjectResult objectDescribe;
        try {
            objectDescribe = Schema.describeSObjects(new List<String>{ objectApiName })[0];
        } catch (InvalidParameterValueException e) {
            throw new InvalidInputException('Unknown object: ' + objectApiName);
        }
        Schema.SObjectField field = objectDescribe.fields.getMap().get(fieldApiName);
        if (field == null) {
            throw new InvalidInputException('Unknown field: ' + objectApiName + '.' + fieldApiName);
        }

        // getPicklistValues() omits inactive values; the isActive() check is a safeguard
        Set<String> activeValues = new Set<String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                activeValues.add(entry.getValue());
            }
        }
        activeValuesByField.put(cacheKey, activeValues);
        return activeValues;
    }

    /**
     * @description Keeps only the allowed entries of a semicolon-delimited value, in their original order.
     * @param currentValue e.g. Red;Blue;Green
     * @param allowedValues The values to keep
     * @return The remaining values joined with semicolons, or null if none remain
     */
    public static String removeDisallowedValues(String currentValue, Set<String> allowedValues) {
        List<String> keptValues = new List<String>();
        for (String rawValue : currentValue.split(MULTI_SELECT_DELIMITER)) {
            String value = rawValue.trim();
            if (allowedValues.contains(value)) {
                keptValues.add(value);
            }
        }

        // Null rather than '' when nothing is left, so the clone's field stays blank
        return keptValues.isEmpty() ? null : String.join(keptValues, MULTI_SELECT_DELIMITER);
    }

    // Describe has no record type dimension, so record type values come from ConnectApi. One call returns
    // every picklist on the object for that record type, so it is cached per object and record type.
    private static Set<String> getRecordTypeValues(String objectApiName, String fieldApiName, String recordTypeId) {
        String cacheKey = (objectApiName + '.' + recordTypeId).toLowerCase();
        if (!valuesByRecordType.containsKey(cacheKey)) {
            valuesByRecordType.put(cacheKey, fetchRecordTypeValues(objectApiName, recordTypeId));
        }

        Map<String, Set<String>> valuesByField = valuesByRecordType.get(cacheKey);
        if (!valuesByField.containsKey(fieldApiName.toLowerCase())) {
            throw new InvalidInputException('No record type picklist values for ' + objectApiName + '.' + fieldApiName);
        }
        return valuesByField.get(fieldApiName.toLowerCase());
    }

    private static Map<String, Set<String>> fetchRecordTypeValues(String objectApiName, String recordTypeId) {
        ConnectApi.PicklistValuesCollection collection;
        try {
            collection = picklistValuesSource != null
                ? picklistValuesSource.getValues(objectApiName, recordTypeId)
                : ConnectApi.RecordUi.getPicklistValuesByRecordType(objectApiName, recordTypeId);
        } catch (Exception e) {
            throw new InvalidInputException(
                'Could not get picklist values for ' + objectApiName + ' record type ' + recordTypeId + ': ' + e.getMessage()
            );
        }

        return toValuesByField(collection);
    }

    @TestVisible
    private static Map<String, Set<String>> toValuesByField(ConnectApi.PicklistValuesCollection collection) {
        Map<String, Set<String>> valuesByField = new Map<String, Set<String>>();
        for (String fieldName : collection.picklistFieldValues.keySet()) {
            Set<String> values = new Set<String>();
            for (ConnectApi.PicklistValue picklistValue : collection.picklistFieldValues.get(fieldName).values) {
                values.add(picklistValue.value);
            }
            valuesByField.put(fieldName.toLowerCase(), values);
        }
        return valuesByField;
    }

    /**
     * @description Seam over ConnectApi so tests can supply picklist values or force a failure
     */
    @TestVisible
    private interface PicklistValuesSource {
        ConnectApi.PicklistValuesCollection getValues(String objectApiName, String recordTypeId);
    }

    /**
     * @description Thrown when the object, field or record type passed in can't be resolved
     */
    public class InvalidInputException extends Exception {
    }

    /**
     * @description Flow input
     */
    public class Request {
        @InvocableVariable(label='Object API Name' description='e.g. Case' required=true)
        public String objectApiName;

        @InvocableVariable(label='Field API Name' description='e.g. Status' required=true)
        public String fieldApiName;

        @InvocableVariable(
            label='Record Type Id'
            description='Optional. When set, also removes values that are not available for this record type, e.g. {!Original_Case.RecordTypeId}'
        )
        public String recordTypeId;

        @InvocableVariable(label='Current Value' description='Picklist value; for multi-select, the semicolon-delimited string')
        public String currentValue;
    }

    /**
     * @description Flow output
     */
    public class Result {
        @InvocableVariable(label='Active Value' description='Semicolon-delimited active values; null if none remain')
        public String activeValue;
    }
}

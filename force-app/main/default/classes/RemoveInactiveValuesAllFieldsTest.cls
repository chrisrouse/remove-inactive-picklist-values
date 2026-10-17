/**
 * @description Tests for RemoveInactiveValuesAllFields. Allowed values come from describe, and the record type
 * lookup is seeded into RemoveInactiveValuesSingleField's cache because ConnectApi can't run in a test.
 */
@IsTest
private class RemoveInactiveValuesAllFieldsTest {
    private static final String FIELD = 'Industry';
    private static final String INACTIVE_VALUE = 'Not An Active Value';

    @IsTest
    static void testCleansPicklistAndReportsChange() {
        String active = activeValues()[0];
        Account original = new Account(Name = 'Original', Industry = INACTIVE_VALUE);

        RemoveInactiveValuesAllFields.Result result = sanitize(original, null, null);

        System.assertEquals(null, ((Account) result.cleanedRecord).Industry);
        System.assertEquals('Original', ((Account) result.cleanedRecord).Name, 'Other fields are preserved');
        System.assertEquals(1, result.changes.size());
        System.assertEquals(FIELD, result.changes[0].fieldApiName);
        System.assertEquals(INACTIVE_VALUE, result.changes[0].originalValue);
        System.assertEquals(INACTIVE_VALUE, original.Industry, 'Input record is not modified');
        System.assertNotEquals(null, active);
    }

    @IsTest
    static void testCleanValueProducesNoChange() {
        String active = activeValues()[0];

        RemoveInactiveValuesAllFields.Result result = sanitize(new Account(Name = 'A', Industry = active), null, null);

        System.assertEquals(active, ((Account) result.cleanedRecord).Industry);
        System.assert(result.changes.isEmpty());
    }

    @IsTest
    static void testFieldApiNamesRestrictsCleaning() {
        Account original = new Account(Name = 'A', Industry = INACTIVE_VALUE);

        RemoveInactiveValuesAllFields.Result result = sanitize(original, new List<String>{ 'Name' }, null);

        System.assertEquals(INACTIVE_VALUE, ((Account) result.cleanedRecord).Industry);
        System.assert(result.changes.isEmpty());
    }

    @IsTest
    static void testNullFieldApiNameEntriesAreIgnored() {
        Account original = new Account(Name = 'A', Industry = INACTIVE_VALUE);

        RemoveInactiveValuesAllFields.Result result = sanitize(original, new List<String>{ null, FIELD }, null);

        System.assertEquals(null, ((Account) result.cleanedRecord).Industry);
    }

    @IsTest
    static void testRequestRecordTypeIdLimitsToRecordTypeValues() {
        // ConnectApi can't run in a test, so seed the record type cache with a list that allows one value
        List<String> active = activeValues();
        Id recordTypeId = masterRecordTypeId();
        RemoveInactiveValuesSingleField.valuesByRecordType.put(
            ('Account.' + recordTypeId).toLowerCase(),
            new Map<String, Set<String>>{ FIELD.toLowerCase() => new Set<String>{ active[0] } }
        );
        Account original = new Account(Name = 'A', Industry = active[1]);

        RemoveInactiveValuesAllFields.Result result = sanitize(original, null, recordTypeId);

        System.assertEquals(null, ((Account) result.cleanedRecord).Industry);
        System.assertEquals(1, result.changes.size());
    }

    @IsTest
    static void testRecordTypeLookupMissingFieldFallsBackToDescribe() {
        List<String> active = activeValues();
        Id recordTypeId = masterRecordTypeId();
        RemoveInactiveValuesSingleField.valuesByRecordType.put(('Account.' + recordTypeId).toLowerCase(), new Map<String, Set<String>>());
        Account original = new Account(Name = 'A', Industry = INACTIVE_VALUE);

        RemoveInactiveValuesAllFields.Result result = sanitize(original, null, recordTypeId);

        System.assertEquals(null, ((Account) result.cleanedRecord).Industry);
        System.assertNotEquals(null, active);
    }

    @IsTest
    static void testPopulatedParentRelationshipIsSkipped() {
        // A populated relationship (Owner) is in the populated fields map but is not a field on the object
        Account original = new Account(Name = 'A');
        original.putSObject('Owner', new User(LastName = 'Owner'));

        RemoveInactiveValuesAllFields.Result result = sanitize(original, null, null);

        System.assert(result.changes.isEmpty());
        System.assertNotEquals(null, result.cleanedRecord);
    }

    @IsTest
    static void testNullRecordReturnsEmptyResult() {
        RemoveInactiveValuesAllFields.Result result = sanitize(null, null, null);

        System.assertEquals(null, result.cleanedRecord);
        System.assert(result.changes.isEmpty());
    }

    @IsTest
    static void testBulkRequests() {
        List<RemoveInactiveValuesAllFields.Request> requests = new List<RemoveInactiveValuesAllFields.Request>();
        for (Integer i = 0; i < 251; i++) {
            RemoveInactiveValuesAllFields.Request request = new RemoveInactiveValuesAllFields.Request();
            request.record = new Account(Name = 'A' + i, Industry = INACTIVE_VALUE);
            requests.add(request);
        }

        List<RemoveInactiveValuesAllFields.Result> results = RemoveInactiveValuesAllFields.sanitize(requests);

        System.assertEquals(251, results.size());
        System.assertEquals(null, ((Account) results[250].cleanedRecord).Industry);
    }

    private static RemoveInactiveValuesAllFields.Result sanitize(SObject record, List<String> fieldApiNames, Id recordTypeId) {
        RemoveInactiveValuesAllFields.Request request = new RemoveInactiveValuesAllFields.Request();
        request.record = record;
        request.fieldApiNames = fieldApiNames;
        request.recordTypeId = recordTypeId;
        return RemoveInactiveValuesAllFields.sanitize(new List<RemoveInactiveValuesAllFields.Request>{ request })[0];
    }

    private static Id masterRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Master').getRecordTypeId();
    }

    private static List<String> activeValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Account.Industry.getDescribe().getPicklistValues()) {
            values.add(entry.getValue());
        }
        System.assert(values.size() >= 2, 'Account.Industry needs at least two active values to run these tests');
        return values;
    }
}

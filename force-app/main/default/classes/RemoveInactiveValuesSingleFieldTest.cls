/**
 * @description Tests for RemoveInactiveValuesSingleField. Active values are read from describe so the tests
 * don't depend on specific picklist values; the "inactive" value is one that is not in the picklist.
 */
@IsTest
private class RemoveInactiveValuesSingleFieldTest {
    private static final String INACTIVE_VALUE = 'Not An Active Value';

    @IsTest
    static void testMultiSelectRemovesInactiveValuesAndKeepsOrder() {
        List<String> active = activeValues('Account', 'Industry');
        System.assert(active.size() >= 2, 'Org needs at least two active values to run this test');

        String input = active[1] + ';' + INACTIVE_VALUE + ';' + active[0];

        Test.startTest();
        List<RemoveInactiveValuesSingleField.Result> results = RemoveInactiveValuesSingleField.filterInactiveValues(
            new List<RemoveInactiveValuesSingleField.Request>{ buildRequest('Account', 'Industry', input) }
        );
        Test.stopTest();

        System.assertEquals(active[1] + ';' + active[0], results[0].activeValue);
    }

    @IsTest
    static void testAllInactiveReturnsNull() {
        List<RemoveInactiveValuesSingleField.Result> results = RemoveInactiveValuesSingleField.filterInactiveValues(
            new List<RemoveInactiveValuesSingleField.Request>{
                buildRequest('Account', 'Industry', INACTIVE_VALUE + ';Other Inactive')
            }
        );

        System.assertEquals(null, results[0].activeValue);
    }

    @IsTest
    static void testBlankValueReturnsNull() {
        List<RemoveInactiveValuesSingleField.Result> results = RemoveInactiveValuesSingleField.filterInactiveValues(
            new List<RemoveInactiveValuesSingleField.Request>{ buildRequest('Account', 'Industry', null) }
        );

        System.assertEquals(null, results[0].activeValue);
    }

    @IsTest
    static void testSinglePicklistsOnDifferentObjects() {
        String accountValue = activeValues('Account', 'Industry')[0];
        String contactValue = activeValues('Contact', 'LeadSource')[0];

        List<RemoveInactiveValuesSingleField.Result> results = RemoveInactiveValuesSingleField.filterInactiveValues(
            new List<RemoveInactiveValuesSingleField.Request>{
                buildRequest('Account', 'Industry', accountValue),
                buildRequest('Account', 'Industry', INACTIVE_VALUE),
                buildRequest('Contact', 'LeadSource', contactValue + ';' + INACTIVE_VALUE)
            }
        );

        System.assertEquals(accountValue, results[0].activeValue);
        System.assertEquals(null, results[1].activeValue);
        System.assertEquals(contactValue, results[2].activeValue);
    }

    @IsTest
    static void testRecordTypeFiltersToValuesAvailableForRecordType() {
        // ConnectApi can't run in a test, so seed the record type cache with a list that allows one value
        List<String> active = activeValues('Account', 'Industry');
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Master').getRecordTypeId();
        RemoveInactiveValuesSingleField.valuesByRecordType.put(
            ('Account.' + recordTypeId).toLowerCase(),
            new Map<String, Set<String>>{ 'industry' => new Set<String>{ active[0] } }
        );

        RemoveInactiveValuesSingleField.Request request = buildRequest('Account', 'Industry', active[0] + ';' + active[1]);
        request.recordTypeId = recordTypeId;

        List<RemoveInactiveValuesSingleField.Result> results = RemoveInactiveValuesSingleField.filterInactiveValues(
            new List<RemoveInactiveValuesSingleField.Request>{ request }
        );

        System.assertEquals(active[0], results[0].activeValue);
    }

    @IsTest
    static void testRecordTypeMissingFieldThrows() {
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Master').getRecordTypeId();
        RemoveInactiveValuesSingleField.valuesByRecordType.put(('Account.' + recordTypeId).toLowerCase(), new Map<String, Set<String>>());
        RemoveInactiveValuesSingleField.Request request = buildRequest('Account', 'Industry', 'a');
        request.recordTypeId = recordTypeId;

        try {
            RemoveInactiveValuesSingleField.filterInactiveValues(new List<RemoveInactiveValuesSingleField.Request>{ request });
            System.assert(false, 'Expected InvalidInputException');
        } catch (RemoveInactiveValuesSingleField.InvalidInputException e) {
            System.assert(e.getMessage().startsWith('No record type picklist values'), e.getMessage());
        }
    }

    @IsTest
    static void testToValuesByFieldReadsConnectApiResponse() {
        ConnectApi.PicklistValue picklistValue = new ConnectApi.PicklistValue();
        picklistValue.value = 'Red';
        ConnectApi.PicklistValues fieldValues = new ConnectApi.PicklistValues();
        fieldValues.values = new List<ConnectApi.PicklistValue>{ picklistValue };
        ConnectApi.PicklistValuesCollection collection = new ConnectApi.PicklistValuesCollection();
        collection.picklistFieldValues = new Map<String, ConnectApi.PicklistValues>{ 'Industry' => fieldValues };

        Map<String, Set<String>> valuesByField = RemoveInactiveValuesSingleField.toValuesByField(collection);

        System.assertEquals(new Set<String>{ 'Red' }, valuesByField.get('industry'));
    }

    @IsTest
    static void testUnknownObjectOrFieldThrows() {
        for (RemoveInactiveValuesSingleField.Request request : new List<RemoveInactiveValuesSingleField.Request>{
            buildRequest('Not_An_Object__c', 'Field__c', 'a'),
            buildRequest('Account', 'Not_A_Field__c', 'a')
        }) {
            try {
                RemoveInactiveValuesSingleField.filterInactiveValues(new List<RemoveInactiveValuesSingleField.Request>{ request });
                System.assert(false, 'Expected InvalidInputException');
            } catch (RemoveInactiveValuesSingleField.InvalidInputException e) {
                System.assert(e.getMessage().startsWith('Unknown'), e.getMessage());
            }
        }
    }

    @IsTest
    static void testRecordTypeValuesAreFetchedOnceAndCached() {
        List<String> active = activeValues('Account', 'Industry');
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Master').getRecordTypeId();
        StubSource stub = new StubSource();
        stub.collection = collectionOf('Industry', active[0]);
        RemoveInactiveValuesSingleField.picklistValuesSource = stub;

        RemoveInactiveValuesSingleField.Request first = buildRequest('Account', 'Industry', active[0] + ';' + active[1]);
        first.recordTypeId = recordTypeId;
        RemoveInactiveValuesSingleField.Request second = buildRequest('Account', 'Industry', active[1]);
        second.recordTypeId = recordTypeId;

        List<RemoveInactiveValuesSingleField.Result> results = RemoveInactiveValuesSingleField.filterInactiveValues(
            new List<RemoveInactiveValuesSingleField.Request>{ first, second }
        );

        System.assertEquals(active[0], results[0].activeValue);
        System.assertEquals(null, results[1].activeValue);
        System.assertEquals(1, stub.calls, 'One ConnectApi call per object and record type');
    }

    @IsTest
    static void testConnectApiFailureThrowsInvalidInput() {
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Master').getRecordTypeId();
        StubSource stub = new StubSource();
        stub.failure = new CalloutException('Record type not found');
        RemoveInactiveValuesSingleField.picklistValuesSource = stub;
        RemoveInactiveValuesSingleField.Request request = buildRequest('Account', 'Industry', 'a');
        request.recordTypeId = recordTypeId;

        try {
            RemoveInactiveValuesSingleField.filterInactiveValues(new List<RemoveInactiveValuesSingleField.Request>{ request });
            System.assert(false, 'Expected InvalidInputException');
        } catch (RemoveInactiveValuesSingleField.InvalidInputException e) {
            System.assert(e.getMessage().startsWith('Could not get picklist values'), e.getMessage());
            System.assert(e.getMessage().contains('Record type not found'), e.getMessage());
        }
    }

    private class StubSource implements RemoveInactiveValuesSingleField.PicklistValuesSource {
        public ConnectApi.PicklistValuesCollection collection;
        public Exception failure;
        public Integer calls = 0;

        public ConnectApi.PicklistValuesCollection getValues(String objectApiName, String recordTypeId) {
            calls++;
            if (failure != null) {
                throw failure;
            }
            return collection;
        }
    }

    private static ConnectApi.PicklistValuesCollection collectionOf(String fieldName, String value) {
        ConnectApi.PicklistValue picklistValue = new ConnectApi.PicklistValue();
        picklistValue.value = value;
        ConnectApi.PicklistValues fieldValues = new ConnectApi.PicklistValues();
        fieldValues.values = new List<ConnectApi.PicklistValue>{ picklistValue };
        ConnectApi.PicklistValuesCollection collection = new ConnectApi.PicklistValuesCollection();
        collection.picklistFieldValues = new Map<String, ConnectApi.PicklistValues>{ fieldName => fieldValues };
        return collection;
    }

    private static RemoveInactiveValuesSingleField.Request buildRequest(String objectName, String fieldName, String value) {
        RemoveInactiveValuesSingleField.Request request = new RemoveInactiveValuesSingleField.Request();
        request.objectApiName = objectName;
        request.fieldApiName = fieldName;
        request.currentValue = value;
        return request;
    }

    private static List<String> activeValues(String objectName, String fieldName) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe()
            .fields.getMap()
            .get(fieldName)
            .getDescribe()
            .getPicklistValues()) {
            values.add(entry.getValue());
        }
        return values;
    }
}

public with sharing class OpportunityTriggerHandler extends TriggerHandler {
    private List<Opportunity> newOpps;
    
    private List<Opportunity> oldOpps;

    private Map<Id, Opportunity> newOppsMap;

    public OpportunityTriggerHandler(List<Opportunity> newOpps, List<Opportunity> oldOpps, Map<Id, Opportunity> newOppsMap) {
        this.newOpps = newOpps;
        this.oldOpps = oldOpps;
        this.newOppsMap = newOppsMap;
    }

    public override void beforeInsert() {
        setOpportunityType();
    }

    public override void afterInsert() {
        insertNewTasks();
    }

    public override void beforeUpdate() {
        validateOpportunityAmount();
        setPrimaryContact();
        updateOpportunityDescription();
    }

    public override void beforeDelete() {
        blockOpportunityDelete();
    }

    public override void afterDelete() {
        notifyOwnersOpportunityDeleted(oldOpps);
    }

    public override void afterUndelete() {
        assignPrimaryContact(newOppsMap);
    }

    private void setOpportunityType() {
        for(Opportunity opp : newOpps) {
                if (opp.Type == null){
                opp.Type = 'New Customer';
            }
            }
    }

    private void validateOpportunityAmount() {
        for(Opportunity opp : newOpps){
            if(opp.Amount < 5000){
                opp.addError('Opportunity amount must be greater than 5000');
            }
        }
    }

    private void blockOpportunityDelete() {
        Set<Id> oldOppAccountIds = new Set<Id>();
        for(Opportunity opp : oldOpps) {
            oldOppAccountIds.add(opp.AccountId);
        }
        if(oldOppAccountIds.isEmpty()) {
            return;
        }
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Industry FROM Account WHERE Id IN :oldOppAccountIds]);
        for(Opportunity opp : oldOpps){
            if(opp.StageName == null || accounts == null) {
                break;
            }
            else if(opp.AccountId != null && ((opp.StageName == 'Closed Won' && (accounts.get(opp.AccountId).Industry == 'Banking')) || opp.IsClosed)){
                    opp.addError('Cannot delete closed opportunity');
                }
    }
}

    private void setPrimaryContact() {
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity opp : newOpps){
            accountIds.add(opp.AccountId);
        }
        
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
        Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

        for (Contact cont : contacts.values()) {
            if (!accountIdToContact.containsKey(cont.AccountId)) {
                accountIdToContact.put(cont.AccountId, cont);
            }
        }

        for(Opportunity opp : newOpps){
            if(opp.Primary_Contact__c == null){
                if (accountIdToContact.containsKey(opp.AccountId)){
                    opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
                }
            }
        }
    }

    private void updateOpportunityDescription() {
        for (Opportunity opp : newOpps){
                if(opp.StageName != null) {
                    opp.Description += '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
                }              
            }
    }

    private void insertNewTasks() {
        List<Task> newTasks = new List<Task>();
            for (Opportunity opp : newOpps){
                Task tsk = new Task();
                tsk.Subject = 'Call Primary Contact';
                tsk.WhatId = opp.Id;
                tsk.WhoId = opp.Primary_Contact__c;
                tsk.OwnerId = opp.OwnerId;
                tsk.ActivityDate = Date.today().addDays(3);
                newTasks.add(tsk);
            }
            insert newTasks;
    }

    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        // Create a list of emails to send
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();

        // Query for the OwnerId of each Opportunity in the provided list
        Map<Id, Opportunity> oppsMap = new Map<Id, Opportunity>([SELECT Id, OwnerId FROM Opportunity WHERE Id IN :opps]);
        
        // Query for the email of the Opportunity owner using the OwnerIds returned in oppsMap
        Map<Id, User> usersMap = new Map<Id, User>([SELECT Id, Email FROM User WHERE Id IN :oppsMap.keySet()]);
        
        // Build the list of Strings for the toAddresses
        List<String> toAddresses;
        for(User u : usersMap.values()) {
            String emailAddress = usersMap.get(u.Id).Email;
            toAddresses.add(emailAddress);
        }

        // Set the values of each email and when done, add the email to the list of emails to send
        for (Opportunity opp : opps){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            // String[] toAddresses = new String[] {[SELECT Id, Email FROM User WHERE Id = :opp.OwnerId].Email};
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {
        // We are going to need the Account Ids of the Opportunities in oppNewMap
        // These Account Ids will link the Opportunities to the Primary Contacts
        // Create a set to hold the Account Ids
        Set<Id> accountIds = new Set<Id>();

        // Loop through oppNewMap to get the Account Ids and store them in the set
        for(Opportunity opp : oppNewMap.values()) {
            accountIds.add(opp.AccountId);
        }

        // Use a map to query for the Ids of the Contacts related to the accounts in the set
        Map<Id, Account> accountMap = new Map<Id, Account>([SELECT Id, Name, (SELECT Id FROM Contacts WHERE Title = 'VP Sales') FROM Account WHERE Id IN :accountIds]);

        // Create a map to hold just the Opportunities that need to be updated at the end        
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();

        // Loop through the undeleted Opps, extract each Account Id, create an Account
        // Create and store the Account's list of related Contacts
        // If the undeleted Opp has no Primary Contact and some related Contacts exist, update Opp
        for(Opportunity opp : oppNewMap.values()) {
            Account acc = accountMap.get(opp.AccountId);
            List<Contact> contacts = acc.Contacts;

            if(opp.Primary_Contact__c == null && !contacts.isEmpty()) {
                Opportunity oppToUpdate = new Opportunity(Id = opp.Id);
                oppToUpdate.Primary_Contact__c = accountMap.get(opp.AccountId).Contacts[0].Id;
                oppMap.put(opp.Id, oppToUpdate);
            }
        }

        update oppMap.values();
    }
}

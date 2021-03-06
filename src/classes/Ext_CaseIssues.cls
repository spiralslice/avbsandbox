public class Ext_CaseIssues {

    Case thisCase;
    Account thisAcc;
    User thisUser;
    Contact thisCon;
    
    Id accid;
    
    //public list<Case_Issue__c> issues { get; set; }
    public list<extIssue> xissues { get; set; }
    
    //Can this user copy associates?
    public Boolean CanCopyAssociates { get; private set; }
    public Boolean CaseCopyAssociates { get; set; }
    public list<String> caseAddresseeIds { get; set; }
    public String caseAdditionalEmails { get; set; }
    
    //Can we create a case on this Account?
    public Boolean CanCreateCase { get; private set; }
    
    //show escalated queue checkbox on page
    public Boolean ShowEscalatedQueue { get; private set; }
    
    //number of Case Issues to display on combined page
    Integer NumIssuesOnPage = 5;
    
    //cjc 06AUG12: changes per dvigil
    /*Department to Case Origin settings
    map<String, String> userdept2caseoriginmap = new map<String, String>
    {
        'CCC' => 'CSO',
        'RS Community' => 'Community',
        'RS Overhead' => 'Regional/Corporate Office',
        'Marketing' => 'Regional/Corporate Office'
    };*/
    
    //Department to Case Origin settings
    //Changed code to reflect position and picklist values 20120806 DVIGIL
    map<String, String> userdept2caseoriginmap = new map<String, String>
    {
        'CCC' => 'CCC - CSO',
        'CCC - FS' => 'CCC - FS',
        'RS Overhead' => 'RS Overhead',
        'RS Community' => 'RS Community',
        'AVB Legal' => 'AVB Legal',
        'Internal Audit' => 'Internal Audit',
        'IS' => 'IS',
        'Law Firm' => 'Law Firm',
        'Marketing' => 'Marketing',
        'SBS' => 'SBS'};
    
    public CaseComment newComment { get; set; }
    public Boolean CreateCaseTask { get; set; }
    public Task newCaseTask { get; set; }
    public list<SelectOption> addresseeOptions { get; private set; }
    public list<SelectOption> ownerOrQueueOptions { get; private set; }
    
    public Ext_CaseIssues(ApexPages.standardController stdcon)
    {
        stdcon.addFields(new list<String> { 'AccountId' });
        if (thisCase == null)
        {
            thisCase = (Case)stdcon.getRecord();
        }
        
        thisUser = [select Id, FirstName, LastName, Department, Profile.Name from User where Id = :Userinfo.getUserId()];
        if (thisCase.AccountId == null)
        {
            accid = (Id)ApexPages.CurrentPage().getParameters().get('accid');
        }
        else
        {
            accid = thisCase.AccountId;
        }
        
        if (accid != null)
        {
            thisAcc = [select Id, Name, Status__c, AccountNumber, Account_ID__c
                from Account
                where Id = :accid];
        }
                
        //show escalated queue only for 'CCC' Profiles
        ShowEscalatedQueue = FALSE;
        if (thisUser.Profile.Name.contains('CCC'))
        {
            ShowEscalatedQueue = TRUE;
        }
        
        //populate case origin
        thisCase.Origin = userdept2caseoriginmap.get(thisUser.Department);
        
        //check to see if this is a Prospect Account
        checkCanCreate();
        
        makeCaseIssues();
        makeAddresseeOptions();
        makeOwnerOrQueueOptions();
        
        newComment = new CaseComment();
        CreateCaseTask = FALSE;
        newCaseTask = new Task();
        
        //Make CanCopyAssociates selective wrt the user's Development_Settings__c Custom Setting
        CanCopyAssociates = FALSE;
        if (Development_Settings__c.getInstance().Can_Copy_Associates_on_Cases__c == TRUE)
            CanCopyAssociates = TRUE;
        
        //Set default
        caseAddresseeIds = new list<String> { 'n/a' };
            
    }
    
    public class extIssue
    {
        public Case_Issue__c issue { get; set; }
        
        public Boolean WillSendEmail { get; set; } //whether to send email on this case issue
        public list<String> addresseeIds { get; set; } //user Ids to address email
        public String additionalEmails { get; set; } //additional email addresses to use
        
        public Boolean WillCreateTask { get; set; } //whether to create new task
        public String OwnerOrQueue { get; set; } //who to assign new task to
        public Task NewTask { get; set; }
        
        public Boolean IsEditable { get; set; }
        
        public extIssue(Case_Issue__c ci)
        {
            this.issue = ci;
            this.NewTask = new Task(OwnerId = Userinfo.getUserId());
            this.OwnerOrQueue = 'Queue';
            this.WillSendEmail = FALSE;
            this.WillCreateTask = FALSE;
            this.addresseeIds = new list<String> { 'n/a' };
        }
    }
    
    private void checkCanCreate()
    {
        CanCreateCase = TRUE;
        /* Removed 081312 JN. Decided against.
        if (accid != null)
        {
            try
            {
                thisCase.Account_Number__c = thisAcc.Account_ID__c;
                
                if ((thisAcc.Status__c == 'Prospect') && (thisCase.Id == null))
                {
                    CanCreateCase = FALSE;
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'You may not create a Case on a Prospect Account.'));
                }
            } catch (Exception e)
            {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Supplied Account Id not found.'));
            }
        }
        */
    }
    
    private void popCaseOrigin()
    {
    }
    
    private void makeOwnerOrQueueOptions()
    {
        ownerOrQueueOptions = new list<SelectOption>
        {
            new SelectOption('Queue', 'Queue'),
            new SelectOption('Owner', 'Person')
        };
    }
    
    private void makeAddresseeOptions()
    {
        addresseeOptions = new list<SelectOption>();
        
        //set of user role ids for this user and anyone directly above them in the hierarchy
        set<id> roleidsUserAndAbove = new set<Id>();
        
        //get all user roles
        map<Id, UserRole> allRolemap = new map<Id, UserRole>([
            select Id, ParentRoleId 
            from UserRole]);
        Id parentId;
        if (Userinfo.getUserRoleId() != null)
        {
            UserRole thisUserRole = allRolemap.get(Userinfo.getUserRoleId());
            parentId = thisUserRole.parentRoleId;
            
            //add the user's own role to the set of roleids to query on 
            //removed 7/20/12 JN: Only include roles above the user, not the user's role
            //roleidsUserAndAbove.add(thisUserRole.Id);
        }
        
        //collect all user roles up the tree until there's a role with no parent role
        while (parentId != null)
        {
            //save the parentId we have
            roleidsUserAndAbove.add(parentId);
            
            //move up the tree one step
            parentId = allRolemap.get(parentId).parentRoleId;
        }
        
        //query for all users that are either in roles above this user, or have CSO or Legal in their title
        list<User> addresseeUsers = [select Id, FirstName, LastName, Title 
            from User 
            where UserRoleId in :roleidsUserAndAbove
                or Title like '%CSO%'
                or Title like '%Legal%'];
        
        //construct addresseeOptions list
        addresseeOptions.add(new SelectOption('n/a','n/a'));
        for (User u : addresseeUsers)
        {
            String optionName = '';
            
            if (u.FirstName != null) optionName += u.FirstName + ' ';
            optionName += u.LastName;
            if (u.Title != null) optionName += ', ' + u.Title;
            
            addresseeOptions.add(new SelectOption(u.Id, optionName));
        }       
    }
    
    private void makeCaseIssues()
    {
        Id caseid;
        list<Case_Issue__c> issues = new list<Case_Issue__c>();
        xissues = new list<extIssue>();
        
        if (thisCase.Id != null)
        {
            caseid = thisCase.Id;
            issues = [select Id, Category__c, Subcategory__c, Amount__c, Type__c, Charge_Type__c, Notes__c, Customer_Group__c, 
            	Case__c, Feedback_level__c
                from Case_Issue__c
                where Case__c = :thisCase.Id];
            
            for (Case_Issue__c ci : issues)
            {
                extIssue newxissue = new extIssue(ci);
                newxissue.IsEditable = FALSE;
                xissues.add(newxissue);
            }
        }
        
        //how many blank lines to add to page? Depends on how many issues there are already
        Integer NumBlankIssues = NumIssuesOnPage - issues.size();
        
        //add at least one no matter what
        if (NumBlankIssues < 1)
            NumBlankIssues = 1;
            
        //populate list up to max
        Integer counter = 0;
        for (Integer i = 0; i < NumBlankIssues; i++)
        {
            Case_Issue__c newissue = new Case_Issue__c(Case__c = thisCase.Id, Feedback_Level__c = 'Neutral');
            issues.add(newissue);
            extIssue newxissue = new extIssue(newissue);
            newxissue.IsEditable = TRUE;
            xissues.add(newxissue);
            counter++;
        }
    }
    
    public PageReference saveCase()
    {
        PageReference pageref = null;
        //save case
        //fulfill requirement for this field in sandbox environment
        Case eblastCase = new Case();
        if (thisCase.Id != null)
        {
            list<Case> eblastCases = [select Eblast_Audience_Distribution_list__c
                from Case
                where Id = :thisCase.Id];
            eblastCase = (eblastCases.size() > 0) ? eblastCases[0] : new Case();
        }
        if (eblastCase.Eblast_Audience_Distribution_list__c == null)
            thisCase.Eblast_Audience_Distribution_list__c = 'required text';
        
        Savepoint sp = Database.setSavepoint();

        try
        {
            thisCon = [select AccountId, FirstName, LastName 
                from Contact 
                where Id = :thisCase.ContactId];
            thisCase.AccountId = thisCon.AccountId;
            
            database.upsert(new list<Case> { thisCase });
            
            //Create Task on Case if necessary
            if (CreateCaseTask)
            {
                newCaseTask.WhoId = thisCase.ContactId;
                newCaseTask.WhatId = thisCase.Id;
                
                insert newCaseTask;
            }
            //save case issues
            saveIssues();
            
            //make Tasks on case issues
            makeTasks();
            
            //send emails on case issues (copy associates)
            sendEmails();
            
            //save case comment
            if (newComment.CommentBody != null)
            {
                CaseComment commenttoinsert = new CaseComment(
                    ParentId = thisCase.Id,
                    CommentBody = newComment.CommentBody);
                insert commenttoinsert;
            }
            
            pageref = new PageReference('/' + thisCase.Id);
        }
        catch (Exception e)
        {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Unable to save: ' + e.getMessage()));
            Database.rollback(sp);
        }
        
        return pageref;
    }
    
    private void makeTasks()
    {
        //go through case issues
        list<Task> taskstoinsert = new list<Task>();
        for (extIssue xi : xissues)
        {
            if ((xi.WillCreateTask) && (xi.IsEditable) && (xi.issue.Id != null))
            {
                //Only accept Owner or Queue determination. The other choice gets blanked out on the new task.
                if (xi.ownerOrQueue == 'Owner')
                {
                    xi.NewTask.Task_Queue__c = null;
                }
                else if (xi.ownerOrQueue == 'Queue')
                {
                    xi.NewTask.OwnerId = UserInfo.getUserId();
                }
                
                xi.NewTask.ActivityDate = system.today();
                xi.NewTask.WhatId = thisCase.Id;
                xi.NewTask.WhoId = thisCase.ContactId;
                //xi.NewTask.Status = 'Not Started';
                xi.NewTask.ActivityDate = system.today();
                xi.NewTask.AVB_Type__c = 'Other';
                xi.NewTask.Subject = 'Task Created through Case page';
                xi.NewTask.Subject_Sub_Category__c = 'Other';
                xi.NewTask.Description = 'Task Created on Case ' + thisCase.CaseNumber + ' and Case Issue ' + xi.issue.Category__c;
                taskstoinsert.add(xi.NewTask);
            }
        }
        
        if (taskstoinsert.size() > 0)
        {
            insert taskstoinsert;
        }
    }
    
    private void sendEmails()
    {
        //collect email addresses for selected Users
        set<Id> userids = new set<Id>();
        for (extIssue xi : xissues)
        {
            if ((xi.WillSendEmail) 
                && (xi.IsEditable) 
                && (xi.issue.Id != null)
                && (!(new set<String> (xi.addresseeIds)).contains('n/a')))
            {
                userids.addall((list<Id>)xi.addresseeIds);
            }
        }
        if ((caseCopyAssociates == TRUE)
            && (!(new set<String>(caseAddresseeIds)).contains('n/a')))
        {
            userids.addall((list<Id>)caseAddresseeIds);
        }
        map<Id, User> userid2usermap = new map<Id, User>([select Id, FirstName, LastName, Email 
            from User 
            where Id in :userids]);
            
        //Construct email messages (one for each checked Case Issue and one for the case)
        list<Messaging.SingleEmailMessage> emailstosend = new list<Messaging.SingleEmailMessage>();
        list<Task> taskstoinsert = new list<Task>();
        for (extIssue xi : xissues)
        {
            String namelist = '';
            if ((xi.WillSendEmail) && (xi.IsEditable) && (xi.issue.Id != null))
            {
                list<String> emailaddresses = new list<String>();
                Boolean firstEmail = TRUE;
                if (!(new set<String> (xi.addresseeIds)).contains('n/a'))
                {
                    for (Id userid : xi.addresseeIds)
                    {
                        User u = userid2usermap.get(userid);
                        emailaddresses.add(u.Email);
                        if (firstEmail)
                        {
                            FirstEmail = FALSE;
                        } else
                        {
                            namelist += ', ';
                        }
                        namelist += ((u.FirstName != null) ? u.FirstName : '') + ' ' + u.LastName;
                            
                            
                    }
                }
                if (xi.additionalEmails.length() > 0)
                    emailaddresses.addAll(xi.additionalEmails.split(';'));
                
                for (String em : emailaddresses)
                {
                    if (firstEmail)
                    {
                        FirstEmail = FALSE;
                    } else
                    {
                        namelist += ', ';
                    }
                    namelist += em;
                }
                if (emailAddresses.size() > 0)
                {
                    Messaging.SingleEmailMessage newemail = makeEmail(emailAddresses, namelist);
                    emailstosend.add(newemail);
                    taskstoinsert.add(makeEmailTask(newemail, namelist));
                }   
            }
        }
        
        //if sending an email
        if (CaseCopyAssociates)
        {
            String namelist = '';
            list<String> emailaddresses = new list<String>();
            Boolean firstEmail = TRUE;
            if (!(new set<String>(caseAddresseeIds)).contains('n/a'))
            {
                for (Id userid : caseAddresseeIds)
                {
system.debug('\n\naddresseeid ' + userid);                  
                    User u = userid2usermap.get(userid);
system.debug('\n\nuser ' + u);                  
                    if (u.Email != null)
                    {
                        emailaddresses.add(u.Email);
                        if (firstEmail)
                        {
                            FirstEmail = FALSE;
                        } else
                        {
                            namelist += ', ';
                        }
                        namelist += ((u.FirstName != null) ? u.FirstName : '') + ' ' + u.LastName;
                    }
                }
            }
            if (caseAdditionalEmails.length() > 0)
                emailaddresses.addAll(caseAdditionalEmails.split(';'));
            
            for (String em : emailaddresses)
            {
                if (firstEmail)
                {
                    FirstEmail = FALSE;
                } else
                {
                    namelist += ', ';
                }
                namelist += em;
            }
            if (emailAddresses.size() > 0)
            {
                Messaging.SingleEmailMessage newemail = makeEmail(emailAddresses, namelist);
                emailstosend.add(newemail);
                taskstoinsert.add(makeEmailTask(newemail, namelist));
            }
        }
        
        //send email list
        if (emailstosend.size() > 0)
            Messaging.sendEmail(emailstosend);
        
        //save email tasks
        if (taskstoinsert.size() > 0)
            insert taskstoinsert;
        
    }
    
    private Task makeEmailTask(Messaging.SingleEmailMessage email, String namelist)
    {
        //save Email as Completed Task on Case
        String descrip = 'Copy Associate email sent on Case  Sent to: ' + namelist + system.today().format() + '.'
            + '<br/>' + email.getHtmlBody();
        
        Task newtask = new Task(
            WhatId = thisCase.Id,
            WhoId = thisCase.ContactId,
            Status = 'Complete',
            ActivityDate = system.today(),
            Subject = 'Email: ' + email.getSubject(),
            Description = descrip);
        
        return newtask;
    }
    
    private Messaging.SingleEmailMessage makeEmail(list<String> emailAddresses, String namelist)
    {
system.debug('\n\nthisUser ' + thisUser);
system.debug('\n\nthisCase ' + thisCase);
system.debug('\n\nthisCon ' + thisCon);
system.debug('\n\nthisAcc ' + thisAcc);
system.debug('\n\namelist ' + namelist);

        
        String emailBody = ((thisUser.FirstName == null) ? '' : thisUser.FirstName + ' ') + thisUser.LastName
            + ' wants to make you aware of the following case:'
            + '<br/><br/>Subject: ' + ((thisCase.Subject == null) ? '' : thisCase.Subject)
            + '<br/>Contact: ' + ((thisCon.FirstName == null) ? '' : thisCon.FirstName + ' ') + thisCon.LastName
            + '<br/>Account: ' + thisAcc.Name
            + '<br/>Feedback Level: ' + ((thisCase.Feedback_Level__c == null) ? 'n/a' : thisCase.Feedback_Level__c)
            + '<br/>Priority: ' + ((thisCase.Priority == null) ? 'n/a' : thisCase.Priority)
            + '<br/>Status: ' + ((thisCase.Status == null) ? 'n/a' : thisCase.Status)
            + '<br/>Comments:<br/>' + ((thisCase.Description == null) ? 'n/a' : thisCase.Description)
            + '<br/><br/>For more details, click the following link:'
            + '<br/>' + URL.getSalesforceBaseUrl().toExternalForm() + '/' + thisCase.Id 
            + '<br/>Associates copied on this case include: ' + namelist;
            
        Messaging.SingleEmailMessage newemail = new Messaging.SingleEmailMessage();
        newemail.setToAddresses(emailaddresses);
        newemail.setWhatId(thisCase.Id);
        newemail.setHTMLBody(emailBody);
        newemail.setSubject('Copy Associate on Case');
        
        return newemail;
    }
    
    public PageReference saveIssues()
    {
        PageReference pageref = null;
        if ((thisCase != null)
            && (thisCase.Id != null))
        {
            list<Case_Issue__c> cistoinsert = new list<Case_Issue__c>();
            
            for (extIssue xi : xissues)
            {
                Case_Issue__c ci = xi.issue;
                
                //If this is a new Case Issue and it has a Category, insert it.
                if ((ci.Category__c != null) && (ci.Id == null))
                {
                    if (ci.Case__c == null)
                	{
                		ci.Case__c = thisCase.Id;
                		ci.Customer_Group__c = thisCase.AccountId;
                	}
                    cistoinsert.add(ci);
                }
            }
            if (cistoinsert.size() > 0)
            {
system.debug('\n\n87 cistoinsert ' + cistoinsert);          
                database.insert(cistoinsert);
            }
            pageref = new PageReference('/' + thisCase.Id);
        }
        return pageref;
    }
    
    public PageReference addRow()
    {
        PageReference pageref = null;
        Case_Issue__c newissue = new Case_Issue__c(Case__c = thisCase.Id);
        //issues.add(newissue);
        extIssue newxissue = new extIssue(newissue);
        newxissue.IsEditable = TRUE;
        xissues.add(newxissue);
    
        return pageref;
    }
}
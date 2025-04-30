public class LoanHistoryFailedPaymentsPrompt {
    //CapabilityType='PromptTemplateType://einstein_gpt__fieldCompletion'
    @InvocableMethod(label='Data Cloud - Failed Transaction'
                     description='Find Failed Transaction from Data Cloud'
                     CapabilityType='PromptTemplateType://einstein_gpt__recordSummary')
    public static List<Response> getSoftDrinkData(List<Request> requests) {
        // Validate the expected number of requests as an input
        
        if (requests.size() != 1)
            throw new ListException('The requests list must contain one entry only');
        Lead acc = requests[0].objectToSummarize;
      List<Loan_History_c_LoanHistory__dlm> loanHistoryList =
    [SELECT No_of_failed_payments__c
     FROM Loan_History_c_LoanHistory__dlm
     WHERE Pan_Number_c__c = :acc.PAN_Number__c];


String responseData;
if (!loanHistoryList.isEmpty()) {
    
    responseData = String.valueOf(loanHistoryList[0].No_of_failed_payments__c);
} else {
    responseData = '0';  // or whatever default makes sense
}

        
        List<Response> responses = new List<Response>();
        Response res = new Response();
        res.Prompt = responseData;
        responses.add(res);
        return responses;
    }
    
    public class Request {
        @InvocableVariable(required=true)
        public Lead objectToSummarize;
    }
    
    public class Response {
        @InvocableVariable
        public String Prompt;
    }
    
}
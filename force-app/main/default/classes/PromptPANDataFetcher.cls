public class PromptPANDataFetcher {

    public class LoanHistoryResponse {
        @InvocableVariable(label='PAN Number' description='PAN Number from the Lead')
        public String panNumber;

        @InvocableVariable(label='Number of Failed Payments')
        public Integer failedPayments;

        @InvocableVariable(label='Message')
        public String message;
    }

    public class LoanHistoryRequest {
        @InvocableVariable(label='PAN Number' description='PAN Number from the Lead')
        public String panNumber;
    }

    @InvocableMethod(label='Fetch Failed Payments by PAN' description='Returns failed payment details for PAN from Data Cloud Loan History')
    public static List<LoanHistoryResponse> getFailedPayments(List<LoanHistoryRequest> requests) {
        List<LoanHistoryResponse> responses = new List<LoanHistoryResponse>();

        for (LoanHistoryRequest req : requests) {
            LoanHistoryResponse res = new LoanHistoryResponse();
            res.panNumber = req.panNumber;

            try {
                Loan_History_c_LoanHistory__dlm loanRecord = [
                    SELECT No_of_failed_payments__c
                    FROM Loan_History_c_LoanHistory__dlm
                    WHERE PanNumber__c = :req.panNumber
                    LIMIT 1
                ];

                res.failedPayments = (Integer)loanRecord.No_of_failed_payments__c;
                res.message = 'Success';
            } catch (Exception e) {
                res.failedPayments = 0;
                res.message = 'Error: ' + e.getMessage();
            }

            responses.add(res);
        }

        return responses;
    }
}
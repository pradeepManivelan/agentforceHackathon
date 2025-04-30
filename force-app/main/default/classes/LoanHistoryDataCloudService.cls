public with sharing class LoanHistoryDataCloudService {
    
    /**
     * Invocable method to retrieve loan history from Data Cloud
     */
    @InvocableMethod(label='Get Customer Loan History' description='Retrieves loan history data from Data Cloud based on PAN number')
    public static List<LoanHistoryResult> getLoanHistory(List<LoanHistoryRequest> requests) {
        List<LoanHistoryResult> results = new List<LoanHistoryResult>();
        
        for (LoanHistoryRequest req : requests) {
            LoanHistoryResult result = new LoanHistoryResult();
            
            try {
                if (String.isBlank(req.panNumber)) {
                    throw new LoanHistoryException('PAN number is required');
                }
                
                // Query loan history records from Data Cloud
                List<Loan_History_c_LoanHistory__dlm> loanHistories = [
                    SELECT Id, Pan_Number_c__c, Status_c__c, Next_scheduled_date__c 
                    FROM Loan_History_c_LoanHistory__dlm 
                    WHERE Pan_Number_c__c = :req.panNumber
                    ORDER BY Next_scheduled_date__c
                ];
                
                if (loanHistories.isEmpty()) {
                    result.foundRecords = false;
                    result.message = 'No loan history records found for the provided PAN number.';
                } else {
                    result.foundRecords = true;
                    
                    // Count failed payments
                    Integer failedPayments = 0;
                    for (Loan_History_c_LoanHistory__dlm loan : loanHistories) {
                        if (loan.Status_c__c == 'Failed') {
                            failedPayments++;
                        }
                    }
                    result.failedPaymentsCount = failedPayments;
                    
                    // Find next pending payment
                    Date nextPaymentDate = null;
                    for (Loan_History_c_LoanHistory__dlm loan : loanHistories) {
                        if (loan.Status_c__c == 'Pending' && loan.Next_scheduled_date__c != null) {
                            if (nextPaymentDate == null || loan.Next_scheduled_date__c < nextPaymentDate) {
                                nextPaymentDate = loan.Next_scheduled_date__c;
                            }
                        }
                    }
                    result.nextPaymentDate = nextPaymentDate;
                    
                    // Build summary message
                    String message = 'Based on your loan history, ';
                    if (failedPayments > 0) {
                        message += 'you have ' + failedPayments + ' failed payment' + (failedPayments > 1 ? 's' : '') + '. ';
                    } else {
                        message += 'you have no failed payments. ';
                    }
                    
                    if (nextPaymentDate != null) {
                        message += 'Your next payment is scheduled for ' + nextPaymentDate.format() + '.';
                    } else {
                        message += 'You have no pending payments scheduled.';
                    }
                    
                    result.message = message;
                }
            } catch (Exception e) {
                result.foundRecords = false;
                result.message = 'Error retrieving loan history: ' + e.getMessage();
                result.errorMessage = e.getMessage();
            }
            
            results.add(result);
        }
        
        return results;
    }
    
    /**
     * Request class for invocable method
     */
    public class LoanHistoryRequest {
        @InvocableVariable(label='PAN Number' description='PAN number to search for loan history' required=true)
        public String panNumber;
    }
    
    /**
     * Result class for invocable method
     */
    public class LoanHistoryResult {
        @InvocableVariable(label='Found Records' description='Whether loan history records were found')
        public Boolean foundRecords;
        
        @InvocableVariable(label='Failed Payments Count' description='Number of failed payments')
        public Integer failedPaymentsCount;
        
        @InvocableVariable(label='Next Payment Date' description='Date of next scheduled payment')
        public Date nextPaymentDate;
        
        @InvocableVariable(label='Message' description='Summary message about loan history')
        public String message;
        
        @InvocableVariable(label='Error Message' description='Error message if retrieval failed')
        public String errorMessage;
        
        public LoanHistoryResult() {
            this.foundRecords = false;
            this.failedPaymentsCount = 0;
        }
    }
    
    /**
     * Custom exception class
     */
    public class LoanHistoryException extends Exception {}
}
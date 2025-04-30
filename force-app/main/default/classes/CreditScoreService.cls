public class CreditScoreService {
    // Credit score endpoint
    private static final String CREDIT_SCORE_ENDPOINT = 'https://api.example.com/credit-score';
    //private static final String CREDIT_SCORE_ENDPOINT = 'callout:CIBIL_API/api/cibil-score?pan=' + EncodingUtil.urlEncode(reqItem.panNumber, 'UTF-8');
    
    /**
     * Gets credit score based on PAN number
     * @param panNumber The PAN number for credit check
     * @return CreditScoreResult containing score category and numeric value
     */
    @AuraEnabled
    public static CreditScoreResult getCreditScore(String panNumber) {
        CreditScoreResult result = new CreditScoreResult();
        
        try {
            // Validate PAN format
            if (!isValidPAN(panNumber)) {
                result.success = false;
                result.errorMessage = 'Invalid PAN number format. Must be 10 alphanumeric characters.';
                return result;
            }
            
            // In a real implementation, this would make a callout to an external service
            // For this mock implementation, we'll simulate a callout
            
            // Mock HTTP callout
             
            HTTP http = new HTTP();
            HTTPRequest request = new HTTPRequest();
            request.setEndpoint(CREDIT_SCORE_ENDPOINT);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setBody('{"panNumber":"' + panNumber + '"}');
            HTTPResponse response = http.send(request);
            
            // Parse response
            if (response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                result.scoreCategory = (String)responseMap.get('category');
                result.scoreValue = (Integer)responseMap.get('score');
                result.success = true;
            } else {
                result.success = false;
                result.errorMessage = 'Failed to retrieve credit score: ' + response.getStatusCode() + ' ' + response.getStatus();
            }
            
            
            // Mock response based on PAN number
            String lastChar = panNumber.substring(9, 10);
            Integer lastDigit;
            try {
                lastDigit = Integer.valueOf(lastChar);
            } catch (Exception e) {
                // Convert letter to number (A=1, B=2, etc.)
                lastDigit = lastChar.charAt(0) - 64;
                if (lastDigit < 1 || lastDigit > 26) lastDigit = 5;
            }
            
            // Use last digit/character to determine score
            if (lastDigit <= 2) {
                result.scoreCategory = 'POOR';
                result.scoreValue = 500 + (lastDigit * 25); // Between 500-550
            } else if (lastDigit <= 5) {
                result.scoreCategory = 'FAIR';
                result.scoreValue = 550 + ((lastDigit-2) * 25); // Between 575-625
            } else if (lastDigit <= 8) {
                result.scoreCategory = 'GOOD';
                result.scoreValue = 650 + ((lastDigit-5) * 25); // Between 675-725
            } else {
                result.scoreCategory = 'EXCELLENT';
                result.scoreValue = 750 + ((lastDigit-8) * 25); // Between 775-800
            }
            
            result.success = true;
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error retrieving credit score: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Validate PAN format (10 characters, alphanumeric)
     */
    private static Boolean isValidPAN(String panNumber) {
        if (panNumber == null || panNumber.length() != 10) {
            return false;
        }
        
        // Check if alphanumeric
        return Pattern.matches('^[A-Za-z0-9]{10}$', panNumber);
    }
    
    /**
     * Result class to hold credit score details
     */
    public class CreditScoreResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String scoreCategory { get; set; }
        @AuraEnabled public Integer scoreValue { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public CreditScoreResult() {
            this.success = false;
            this.scoreCategory = '';
            this.scoreValue = 0;
            this.errorMessage = '';
        }
    }
}
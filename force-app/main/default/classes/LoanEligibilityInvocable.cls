public with sharing class LoanEligibilityInvocable {
    
    // Credit score mapping
    private static final Map<String, Integer> CREDIT_SCORE_MAP = new Map<String, Integer>{
        'POOR' => 500,
        'FAIR' => 600,
        'GOOD' => 700,
        'EXCELLENT' => 800
    };
    
    // Employment status weight
    private static final Map<String, Decimal> EMPLOYMENT_STATUS_WEIGHT = new Map<String, Decimal>{
        'NOT EMPLOYED' => 0.0,
        'PART TIME' => 0.7,
        'FULL TIME' => 1.0
    };
    
    /**
     * Invocable method to calculate loan eligibility
     * This method can be called from Agentforce
     */
    @InvocableMethod(label='Calculate Loan Eligibility' description='Calculates eligibility score based on financial information')
    public static List<LoanEligibilityResult> calculateEligibility(List<LoanEligibilityRequest> requests) {
        List<LoanEligibilityResult> results = new List<LoanEligibilityResult>();
        
        for (LoanEligibilityRequest req : requests) {
            LoanEligibilityResult result = new LoanEligibilityResult();
            
            try {
                // Validate inputs
                if (req.annualIncome <= 0) {
                    throw new LoanEligibilityException('Annual income must be greater than zero');
                }
                
                if (req.existingDebtPerMonth < 0) {
                    throw new LoanEligibilityException('Existing debt cannot be negative');
                }
                
                if (req.loanAmount <= 0) {
                    throw new LoanEligibilityException('Loan amount must be greater than zero');
                }
                
                String empStatus = req.employmentStatus != null ? req.employmentStatus.toUpperCase() : null;
                if (empStatus == null || !EMPLOYMENT_STATUS_WEIGHT.containsKey(empStatus)) {
                    throw new LoanEligibilityException('Invalid employment status');
                }
                
                // Get credit score (from parameter or API)
                Integer creditScoreValue;
                if (String.isBlank(req.creditScore)) {
                    if (String.isBlank(req.panNumber)) {
                        throw new LoanEligibilityException('PAN number required for credit check when credit score is not provided');
                    }
                    
                    // Get credit score from CIBIL API using CibilAgentforceAction
                    Map<String, Object> cibilResult = getCreditScoreFromCIBIL(req.panNumber);
                    creditScoreValue = (Integer)cibilResult.get('score');
                    result.creditScoreCategory = (String)cibilResult.get('bandName');
                } else {
                    // Use provided credit score
                    if (CREDIT_SCORE_MAP.containsKey(req.creditScore.toUpperCase())) {
                        creditScoreValue = CREDIT_SCORE_MAP.get(req.creditScore.toUpperCase());
                        result.creditScoreCategory = req.creditScore.toUpperCase();
                    } else {
                        try {
                            // Try parsing as direct number
                            creditScoreValue = Integer.valueOf(req.creditScore);
                            result.creditScoreCategory = getCreditScoreCategory(creditScoreValue);
                        } catch (Exception e) {
                            throw new LoanEligibilityException('Invalid credit score format');
                        }
                    }
                }
                
                // Calculate debt-to-income ratio
                Decimal monthlyIncome = req.annualIncome / 12;
                Decimal debtToIncomeRatio = (req.existingDebtPerMonth / monthlyIncome) * 100;
                result.debtToIncomeRatio = debtToIncomeRatio;
                
                // Check immediate disqualifiers
                if (debtToIncomeRatio > 65) {
                    result.eligibilityScore = 0;
                    result.reason = 'Debt-to-income ratio exceeds 65%';
                    results.add(result);
                    continue;
                }
                
                if (creditScoreValue < 600 && req.loanAmount > 1000000) {
                    result.eligibilityScore = 15; // Very low eligibility
                    result.reason = 'Credit score too low for requested loan amount';
                    results.add(result);
                    continue;
                }
                
                if (EMPLOYMENT_STATUS_WEIGHT.get(empStatus) == 0) {
                    result.eligibilityScore = 0;
                    result.reason = 'Unemployed applicants are not eligible';
                    results.add(result);
                    continue;
                }
                
                // Verify affordability over 10 years
                Decimal maxMonthlyPayment = (monthlyIncome * 0.35) - req.existingDebtPerMonth; // 35% of income minus existing debt
                Decimal monthlyLoanPaymentAt10Years = calculateMonthlyPayment(req.loanAmount, 10 * 12, 0.08); // Assuming 8% interest
                Decimal futureIncome = req.annualIncome * 1.1; // 10% increase in income
                Decimal futureMonthlyIncome = futureIncome / 12;
                Decimal futureMaxMonthlyPayment = (futureMonthlyIncome * 0.35) - req.existingDebtPerMonth;
                
                if (monthlyLoanPaymentAt10Years > futureMaxMonthlyPayment) {
                    result.eligibilityScore = 20; // Very low eligibility
                    result.reason = 'Loan amount too high to be paid within 10 years even with 10% income growth';
                    results.add(result);
                    continue;
                }
                
                // Progressive scoring based on factors
                // 1. Credit Score: 0-30 points
                Decimal creditScorePoints = 0;
                if (creditScoreValue < 550) creditScorePoints = 0;
                else if (creditScoreValue < 650) creditScorePoints = 15;
                else if (creditScoreValue < 750) creditScorePoints = 25;
                else creditScorePoints = 30;
                
                // 2. Debt-to-Income Ratio: 0-30 points
                Decimal dtiPoints = 0;
                if (debtToIncomeRatio > 55) dtiPoints = 5;
                else if (debtToIncomeRatio > 45) dtiPoints = 15;
                else if (debtToIncomeRatio > 35) dtiPoints = 20;
                else if (debtToIncomeRatio > 25) dtiPoints = 25;
                else dtiPoints = 30;
                
                // 3. Employment Status: 0-20 points
                Decimal employmentPoints = 20 * EMPLOYMENT_STATUS_WEIGHT.get(empStatus);
                
                // 4. Loan Affordability: 0-20 points
                Decimal affordabilityRatio = monthlyLoanPaymentAt10Years / maxMonthlyPayment;
                Decimal affordabilityPoints = 0;
                
                if (affordabilityRatio > 1) affordabilityPoints = 0;
                else if (affordabilityRatio > 0.8) affordabilityPoints = 5;
                else if (affordabilityRatio > 0.6) affordabilityPoints = 10;
                else if (affordabilityRatio > 0.4) affordabilityPoints = 15;
                else affordabilityPoints = 20;
                
                // Calculate total eligibility score
                Decimal totalScore = creditScorePoints + dtiPoints + employmentPoints + affordabilityPoints;
                
                // Final adjustments based on specific scenarios
                if (creditScoreValue >= 750 && debtToIncomeRatio < 30 && 
                    EMPLOYMENT_STATUS_WEIGHT.get(empStatus) == 1.0) {
                    totalScore = Math.min(100, totalScore + 10); // Bonus for excellent credit + low DTI + full-time
                }
                
                if (creditScoreValue < 600 && req.loanAmount <= 500000) {
                    totalScore = Math.min(100, totalScore + 15); // Small loan amount helps offset poor credit
                }
                
                // Set result values
                result.eligibilityScore = totalScore.intValue();
                result.creditScoreValue = creditScoreValue;
                
                // Set recommendation based on score
                if (totalScore >= 80) {
                    result.recommendation = 'Highly eligible for loan';
                } else if (totalScore >= 60) {
                    result.recommendation = 'Eligible for loan with standard terms';
                } else if (totalScore >= 40) {
                    result.recommendation = 'Eligible for loan with higher interest rate';
                } else if (totalScore >= 20) {
                    result.recommendation = 'May be eligible for reduced loan amount';
                } else {
                    result.recommendation = 'Not recommended for loan approval';
                }
                
                // Update lead if provided
                if (req.leadId != null || String.isNotBlank(req.email)) {
                    // Collect financial data to save to lead
                    Map<String, Object> financialData = new Map<String, Object>{
                        'annualIncome' => req.annualIncome,
                            'existingDebtPerMonth' => req.existingDebtPerMonth,
                            'employmentStatus' => req.employmentStatus,
                            'loanAmount' => req.loanAmount,
                            'panNumber' => req.panNumber
                            };
                                
                                upsertLead(req.leadId, req.email, req.firstName, req.lastName, result, financialData);
                }
                
            } catch (LoanEligibilityException e) {
                result.eligibilityScore = 0;
                result.reason = e.getMessage();
            } catch (Exception e) {
                result.eligibilityScore = 0;
                result.reason = 'Error calculating eligibility: ' + e.getMessage();
            }
            
            results.add(result);
        }
        
        return results;
    }
    
    /**
     * Update a lead with eligibility results
     */
/**
 * Create or update a lead with eligibility results
 * @param leadId Optional existing Lead ID
 * @param email Email address to match existing Lead or create new one
 * @param firstName First name for new Lead
 * @param lastName Last name for new Lead
 * @param result Eligibility results to save
 * @param financialData Additional financial data to save
 */
    private static void upsertLead(
        Id leadId, 
        String email, 
        String firstName, 
        String lastName,
        LoanEligibilityResult result,
        Map<String, Object> financialData
    ) {
        try {
            Lead ld;
            
            // If Lead ID is provided, use it
            if (leadId != null) {
                ld = new Lead(Id = leadId);
            } 
            // Otherwise, try to find by email
            else if (String.isNotBlank(email)) {
                List<Lead> existingLeads = [SELECT Id FROM Lead WHERE Email = :email LIMIT 1];
                
                if (!existingLeads.isEmpty()) {
                    ld = new Lead(Id = existingLeads[0].Id);
                } else {
                    // Create new Lead if not found
                    ld = new Lead();
                    ld.Email = email;
                    ld.FirstName = firstName;
                    ld.LastName = lastName != null ? lastName : 'Unknown';
                    ld.Company = lastName != null ? lastName + ' Household' : 'Individual Customer';
                    ld.Status = 'Open';
                    ld.LeadSource = 'Website';
                }
            } else {
                // Cannot create or update without ID or email
                throw new LoanEligibilityException('Either Lead ID or Email is required for Lead creation/update');
            }
            
            // Set eligibility results
            ld.Eligibility_Score__c = result.eligibilityScore;
            ld.Credit_Score__c = result.creditScoreCategory;
            ld.Debt_To_Income_Ratio__c = result.debtToIncomeRatio;
            ld.Eligibility_Reason__c = result.reason;
            ld.Eligibility_Recommendation__c = result.recommendation;
            
            // Set financial data if provided
            if (financialData != null) {
                if (financialData.containsKey('annualIncome'))
                    ld.Annual_Income__c = (Decimal)financialData.get('annualIncome');
                
                if (financialData.containsKey('existingDebtPerMonth'))
                    ld.Existing_Debt_Per_Month__c = (Decimal)financialData.get('existingDebtPerMonth');
                
                if (financialData.containsKey('employmentStatus'))
                    ld.Employment_Status__c = (String)financialData.get('employmentStatus');
                
                if (financialData.containsKey('loanAmount'))
                    ld.Loan_Amount__c = (Decimal)financialData.get('loanAmount');
                
                if (financialData.containsKey('panNumber'))
                    ld.PAN_Number__c = (String)financialData.get('panNumber');
            }
            
            // Upsert the lead
            upsert ld;
            
            // Store the lead ID in the result
            result.leadId = ld.Id;
            result.leadUpdated = true;
        } catch (Exception e) {
            result.leadUpdated = false;
            result.leadUpdateError = e.getMessage();
        }
    }
    
    /**
     * Get credit score from CIBIL API using CibilAgentforceAction
     * Returns a map with 'score' (integer) and 'band' (string) keys
     */
    private static Map<String, Object> getCreditScoreFromCIBIL(String panNumber) {
        // Validate PAN format
        if (String.isBlank(panNumber) || panNumber.length() != 10 || !Pattern.matches('^[A-Za-z0-9]{10}$', panNumber)) {
            throw new LoanEligibilityException('Invalid PAN number format. Must be 10 alphanumeric characters.');
        }
        
        // Create request for CibilAgentforceAction
        CibilAgentforceAction.RequestWrapper req = new CibilAgentforceAction.RequestWrapper();
        req.panNumber = panNumber;
        
        // Call CibilAgentforceAction
        List<CibilAgentforceAction.ResponseWrapper> cibilResults = CibilAgentforceAction.getCibilScore(new List<CibilAgentforceAction.RequestWrapper>{req});
        
        if (cibilResults.isEmpty()) {
            throw new LoanEligibilityException('Failed to retrieve credit score: No response from CIBIL API');
        }
        
        // Parse the result message to extract score and band
        String resultMessage = cibilResults[0].result;
        
        // Check if the result indicates an error
        if (resultMessage.startsWith('Error:') || resultMessage.startsWith('Exception:')) {
            throw new LoanEligibilityException('Failed to retrieve credit score: ' + resultMessage);
        }
        
        // Parse the score and band from the result message
        // Expected format: "CIBIL Score for PAN ABCDE1234F is 750 (Good)"
        Integer score;
        String bandName;
        
        try {
            // Extract score
            Integer scoreStartIndex = resultMessage.indexOf('is ') + 3;
            Integer scoreEndIndex = resultMessage.indexOf(' (');
            String scoreStr = resultMessage.substring(scoreStartIndex, scoreEndIndex).trim();
            score = Integer.valueOf(scoreStr);
            
            // Extract band
            Integer bandStartIndex = resultMessage.indexOf('(') + 1;
            Integer bandEndIndex = resultMessage.indexOf(')');
            bandName = resultMessage.substring(bandStartIndex, bandEndIndex).trim().toUpperCase();
            
            // Normalize band names to match our categories
            if (bandName == 'AVERAGE') {
                bandName = 'GOOD'; // Map 'Average' to 'GOOD' for consistency
            }
        } catch (Exception e) {
            throw new LoanEligibilityException('Failed to parse credit score from response: ' + resultMessage);
        }
        
        Map<String, Object> result = new Map<String, Object>();
        result.put('score', score);
        result.put('bandName', bandName);
        return result;
    }
    
    /**
     * Get credit score category from numeric value
     */
    private static String getCreditScoreCategory(Integer score) {
        if (score < 550) return 'POOR';
        else if (score < 650) return 'FAIR';
        else if (score < 750) return 'GOOD';
        else return 'EXCELLENT';
    }
    
    /**
     * Calculate monthly payment for a loan
     */
    private static Decimal calculateMonthlyPayment(Decimal principal, Integer termInMonths, Decimal annualInterestRate) {
        // Convert to Double for Math.pow operations
        Double monthlyRate = annualInterestRate.doubleValue() / 12;
        Double principalDbl = principal.doubleValue();
        
        // Calculate using Math.pow
        Double factor = Math.pow(1 + monthlyRate, termInMonths);
        Double payment = principalDbl * (monthlyRate * factor) / (factor - 1);
        
        // Convert back to Decimal for financial precision
        return Decimal.valueOf(payment);
    }
    
    /**
     * Request class for invocable method
     */
    public class LoanEligibilityRequest {
        @InvocableVariable(label='Annual Income' description='Annual income of the applicant' required=true)
        public Decimal annualIncome;
        
        @InvocableVariable(label='Existing Debt Per Month' description='Monthly debt obligations' required=true)
        public Decimal existingDebtPerMonth;
        
        @InvocableVariable(label='Credit Score' description='Credit score category or value (optional if PAN provided)')
        public String creditScore;
        
        @InvocableVariable(label='Employment Status' description='Current employment status (NOT EMPLOYED, PART TIME, FULL TIME)' required=true)
        public String employmentStatus;
        
        @InvocableVariable(label='Loan Amount' description='Requested loan amount' required=true)
        public Decimal loanAmount;
        
        @InvocableVariable(label='PAN Number' description='PAN for credit check (required if credit score not provided)')
        public String panNumber;
        
        @InvocableVariable(label='Lead ID' description='ID of existing Lead record (optional)')
        public Id leadId;
        
        @InvocableVariable(label='Email' description='Email address for Lead creation/matching')
        public String email;
        
        @InvocableVariable(label='First Name' description='First name for Lead creation')
        public String firstName;
        
        @InvocableVariable(label='Last Name' description='Last name for Lead creation')
        public String lastName;
    }
    
    /**
     * Result class for invocable method
     */
    public class LoanEligibilityResult {
        @InvocableVariable(label='Eligibility Score' description='Calculated eligibility score (0-100)')
        public Integer eligibilityScore;
        
        @InvocableVariable(label='Reason' description='Reason for eligibility score or rejection')
        public String reason;
        
        @InvocableVariable(label='Recommendation' description='Loan approval recommendation')
        public String recommendation;
        
        @InvocableVariable(label='Credit Score Category' description='Credit score category (POOR, FAIR, GOOD, EXCELLENT)')
        public String creditScoreCategory;
        
        @InvocableVariable(label='Credit Score Value' description='Numeric credit score value')
        public Integer creditScoreValue;
        
        @InvocableVariable(label='Debt To Income Ratio' description='Calculated debt-to-income ratio')
        public Decimal debtToIncomeRatio;
        
        @InvocableVariable(label='Lead Updated' description='Whether lead record was successfully updated')
        public Boolean leadUpdated;
        
        @InvocableVariable(label='Lead Update Error' description='Error message if lead update failed')
        public String leadUpdateError;
        
        @InvocableVariable(label='Lead ID' description='ID of the created or updated Lead')
        public Id leadId;
        
        public LoanEligibilityResult() {
            this.eligibilityScore = 0;
            this.reason = '';
            this.recommendation = '';
            this.creditScoreValue = 0;
            this.leadUpdated = false;
        }
    }
    
    /**
     * Custom exception class
     */
    public class LoanEligibilityException extends Exception {}
}
package com.hipstershop.paymentservicejava;

import java.io.InputStream;
import java.net.URL;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Random;
import java.util.logging.Logger;

import javax.persistence.LockTimeoutException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.hipstershop.paymentservicejava.dataaccess.PaymentRecordRepository;
import com.hipstershop.paymentservicejava.model.PaymentRecord;

import hipstershop.Payment.ChargeRequest;

@Component
public class PaymentController {

    private Logger log = Logger.getLogger("PaymentController");

    @Autowired
    PaymentRecordRepository repo;

    private static boolean envBool(String name, boolean def) {
        String v = System.getenv(name);
        if (v == null || v.isBlank()) return def;
        return "1".equals(v) || "true".equalsIgnoreCase(v) || "yes".equalsIgnoreCase(v);
    }

    private static double envDouble(String name, double def) {
        String v = System.getenv(name);
        if (v == null || v.isBlank()) return def;
        try {
            return Double.parseDouble(v);
        } catch (Exception e) {
            return def;
        }
    }

    public String clearPayment(ChargeRequest request) throws LockTimeoutException {
        String currency = request.getAmount().getCurrencyCode();
        Long amount = request.getAmount().getUnits();
        int nanos = request.getAmount().getNanos();
        String ccNumber = request.getCreditCard().getCreditCardNumber();

        // perform payment "API call"
        // This service intentionally contains failure modes; keep them configurable so local dev can be stable.
        boolean rateLimited = envBool("TSRE_PAYMENT_RATE_LIMITED", false);
        try {
            URL u = new URL("https://developer.paypal.com/");
            InputStream in = u.openStream();
            new String(in.readAllBytes(), StandardCharsets.UTF_8); 
            log.info(String.format("Processing transaction: %s ending %s Amount: %s%d.%d", 
            this.getCardtypeByNumber(ccNumber), 
            ccNumber.substring(ccNumber.length()-5), 
            currency,
            amount,
            nanos));
        } catch (Exception e) {
            rateLimited = true;
            e.printStackTrace();
        }

        // Failure injection: disabled by default. Example: TSRE_PAYMENT_LOCK_TIMEOUT_PROB=0.5
        double lockTimeoutProb = envDouble("TSRE_PAYMENT_LOCK_TIMEOUT_PROB", 0.0);
        Random r = new Random(System.currentTimeMillis());
        if (lockTimeoutProb > 0.0 && r.nextDouble() < lockTimeoutProb) {
            for(double i=0; i<500000; i++) { // let's waste some time to make it look like we're waiting for a table lock
                Math.sqrt(i);
            }
            throw new LockTimeoutException("Lock wait timeout exceeded; try restarting transaction");
        } 

        if(rateLimited) {
                // let's make sure we do not have this request in our database already
                Iterable<PaymentRecord> records = this.repo.findAll();
                for(PaymentRecord record : records) {
                    if(record.getCreditcardnumber().equals(ccNumber) && record.getAmount() == amount.doubleValue()) {
                        log.info("Payment already on record!?");
                    }
                }
                // persist payment data to the database in case we need to retry later due to rate limits
                PaymentRecord rec = new PaymentRecord();
                String amountS = String.valueOf(amount) + "." + String.valueOf(nanos);
                rec.setAmount(Double.parseDouble(amountS));
                rec.setCreditcardnumber(ccNumber);
                rec.setCvvcode(String.valueOf(request.getCreditCard().getCreditCardCvv()));
                rec.setExpirationMonth(request.getCreditCard().getCreditCardExpirationMonth());
                rec.setExpirationYear(request.getCreditCard().getCreditCardExpirationYear());
                rec.setPaymentstatus("transaction rate limited");
                repo.save(rec);
        } 
        return generateTransactionId();
    }

    private String generateTransactionId() {
        byte[] array = new byte[7]; // length is bounded by 7
        new Random().nextBytes(array);
        return new String(array, Charset.forName("UTF-8"));
    }


    private String getCardtypeByNumber(String creditcardNumber) {
        if(creditcardNumber.startsWith("4")) {
            return "Visa";
        } else if(creditcardNumber.startsWith("34") || creditcardNumber.startsWith("37")) {
            return "American Express";
        } else if(creditcardNumber.startsWith("5")) {
            return "Mastercard";
        } else {
            return "other";
        }

    }
}

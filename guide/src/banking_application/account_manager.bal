// Copyright (c) 2018 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/config;
import ballerina/log;
import ballerina/io;
import ballerinax/java.jdbc;
import ballerina/transactions;

string host = config:getAsString("DATABASE_HOST", "localhost");
int port = config:getAsInt("DATABASE_PORT", 3306);
string name = config:getAsString("DATABASE_NAME", "bankDB");
string url = "jdbc:mysql://" + host + ":" + io:sprintf("%s", port) + "/" + name;

// 'jdbc:Client'.
jdbc:Client bankDB = new({
    url: url,
    username: config:getAsString("DATABASE_USERNAME", "root"),
    password: config:getAsString("DATABASE_PASSWORD", "root"),
    dbOptions: { useSSL: false }
});

// Function to add users to 'ACCOUNT' table of 'bankDB' database.
public function createAccount(string name) returns @tainted (int|error) {
    // Insert query.
    var updateRet = bankDB->update("INSERT INTO ACCOUNT (USERNAME, BALANCE) VALUES (?, ?)", name, 0);
    if (updateRet is error) {
        log:printError("Error occurred during database operation", err = updateRet);
        return updateRet;
    }
    // Get the primary key of the last insertion (Auto incremented value).
    var selectRet = bankDB->select("SELECT LAST_INSERT_ID() AS ACCOUNT_ID from ACCOUNT where ?", (), 1);
    int|error retVal = -1;
    if (selectRet is table<record {}>) {
        // convert the table to json
        var jsonConvertRet = json.constructFrom(selectRet);
        int|error returnVal;
        if (jsonConvertRet is json) {
            json[] ret = <json[]>jsonConvertRet;
            retVal = int.constructFrom(checkpanic ret[0]?.ACCOUNT_ID);
            if (retVal is int) {
                log:printInfo(io:sprintf("Account ID for user: '%s': %s", name, retVal));
            }
        } else {
            retVal = jsonConvertRet;
            log:printError("Error occurred during JSON conversion", err = jsonConvertRet);
        }
        // Since we are not fully iterating the json value converted from the table we need to explicitly close the table
        // to avoid connection leak. If the json was fully iterated, the table would also have been fully iterated and
        // streamed out and then the connection would have been automatically closed.
        selectRet.close();
    } else {
        retVal = selectRet;
        log:printError("Error occurred during database operation", err = selectRet);
    }
    // Return the primary key, which will be the account number of the account or an error in case of a failure
    return retVal;
}

// Function to verify an account whether it exists or not.
public function verifyAccount(int accId) returns @tainted (boolean|error) {
    log:printInfo(io:sprintf("Verifying whether account ID %s exists", accId));
    // SQL query parameters.
    // Select query to check whether account exists.
    var selectRet = bankDB->select("SELECT COUNT(*) AS COUNT FROM ACCOUNT WHERE ID = ?", (), accId);
    boolean|error retVal = false;
    if (selectRet is table<record {}>) {
        // convert the table to json.
        var jsonConvertRet = json.constructFrom(selectRet);
        if (jsonConvertRet is json) {
            // convert the json to int.
            json[] ret = <json[]>jsonConvertRet;
            int count = <int>ret[0]?.COUNT;
            // Return a boolean, which will be true if account exists; false otherwise.
            retVal = convertToBoolean(count);
        } else {
            retVal = jsonConvertRet;
        }
        // Since we are not fully iterating the json value converted from the table we need to explicitly close the table
        // to avoid connection leak. If the json was fully iterated, the table would also have been fully iterated and
        // streamed out and then the connection would have been automatically closed.
        selectRet.close();
    } else {
        retVal = selectRet;
    }
    return retVal;
}

function convertToBoolean(int intVal) returns boolean {
    if (intVal > 0) {
        return true;
    } else {
        return false;
    }
}

// Function to check balance in an account.
public function checkBalance(int accId) returns @tainted (int|error) {
    // Verify account whether it exists and return an error if not.
    var accountVerificationRet = verifyAccount(accId);
    if (accountVerificationRet is error) {
        return accountVerificationRet;
    } else {
        if (!accountVerificationRet) {
            error err = error("Error: Account does not exist");
            return err;
        }
    }
    int|error retVal = -1;
    // Select query to get balance.
    var selectRet = bankDB->select("SELECT BALANCE FROM ACCOUNT WHERE ID = ?", (), accId);
    if (selectRet is table<record {}>) {
        // convert the table to json.
        var jsonConvertRet = json.constructFrom(selectRet);
        if (jsonConvertRet is json) {
            // convert the json to int.
            json[] ret = <json[]>jsonConvertRet;
            int balance = <int>ret[0]?.BALANCE;
            retVal = balance;
            log:printInfo(io:sprintf("Available balance in account ID %s: %s", accId, balance));
        } else {
            retVal = jsonConvertRet;
        }
        // Since we are not fully iterating the json value converted from the table we need to explicitly close the table
        // to avoid connection leak. If the json was fully iterated, the table would also have been fully iterated and
        // streamed out and then the connection would have been automatically closed.
        selectRet.close();
    } else {
        retVal = selectRet;
    }
    // Return the balance or error in case of a failure.
    return retVal;
}

// Function to deposit money to an account.
public function depositMoney(int accId, int amount) returns @tainted error|() {
    // Check whether the amount specified is valid and return an error if not.
    if (amount <= 0) {
        error err = error("Error: Invalid amount");
        return err;
    }
    var accountVerificationRet = verifyAccount(accId);
    if (accountVerificationRet is error) {
        return accountVerificationRet;
    } else {
        if (!accountVerificationRet) {
            // Verify account whether it exists and return an error if not.
            error err = error("Error: Account does not exist");
            return err;
        }
    }
    log:printInfo(io:sprintf("Depositing money to account ID: %s", accId));
    // Update query to increase the current balance.
    var updateRet = bankDB->update("UPDATE ACCOUNT SET BALANCE = (BALANCE + ?) WHERE ID = ?", amount, accId);
    if (updateRet is jdbc:UpdateResult) {
        log:printInfo(io:sprintf("$%s has been deposited to account ID %s", amount, accId));
    } else {
        return updateRet;
    }
    return;
}

// Function to withdraw money from an account.
public function withdrawMoney(int accId, int amount) returns @tainted (error|()) {
    // Check whether the amount specified is valid and return an error if not.
    if (amount <= 0) {
        error err = error("Error: Invalid amount");
        return err;
    }
    // Check current balance.
    var balanceVal = checkBalance(accId);
    if (balanceVal is int) {
        // Check whether the user has enough money to withdraw the requested amount and return an error if not.
        if (balanceVal < amount) {
            error err = error("Error: Not enough balance");
            return err;
        }
    } else {
        return balanceVal;
    }
    log:printInfo(io:sprintf("Withdrawing money from account ID: %s", accId));
    // Update query to reduce the current balance.
    var updateRet = bankDB->update("UPDATE ACCOUNT SET BALANCE = (BALANCE - ?) WHERE ID = ?", amount, accId);
    if (updateRet is jdbc:UpdateResult) {
        log:printInfo(io:sprintf("$%s has been withdrawn from account ID %s", amount, accId));
    } else {
        return updateRet;
    }
    return;
}

// Function to transfer money from one account to another.
public function transferMoney(int fromAccId, int toAccId, int amount) returns boolean {
    boolean isSuccessful = false;
    log:printInfo("Initiating transaction");
    // Transaction block - Ensures the 'ACID' properties.
    // Withdraw and deposit should happen as a transaction when transferring money from one account to another.
    // Here, the reason for switching off the 'retries' option is, in failing scenarios almost all the time
    // transaction fails due to erroneous operations triggered by the users.
    transaction with retries = 0 {
        // Withdraw money from transferor's account.
        var withdrawRet = withdrawMoney(fromAccId, amount);
        if (withdrawRet is ()) {
            var depositRet = depositMoney(toAccId, amount);
            if (depositRet is ()) {
                isSuccessful = true;
            } else {
                log:printError("Error while depositing the money: " + depositRet.reason());
                // Abort transaction if deposit fails.
                log:printError(io:sprintf("Failed to transfer money from account ID %s to account ID %s", fromAccId,
                        toAccId));
                abort;
            }
        } else {
            log:printError("Error while withdrawing the money: " + withdrawRet.reason());
            // Abort transaction if withdrawal fails.
            log:printError(io:sprintf("Failed to transfer money from account ID %s to account ID %s", fromAccId,
                    toAccId));
            abort;
        }
    } committed {
        log:printInfo("Transaction: " + transactions:getCurrentTransactionId() + " committed");
        // If transaction successful.
        log:printInfo(io:sprintf("Successfully transferred $%s from account ID %s to account ID %s",
                amount, fromAccId, toAccId));
    } aborted {
        log:printInfo("Transaction: " + transactions:getCurrentTransactionId() + " aborted");
    }
    return isSuccessful;
}
<?php

// ---------------------------------------------------------------
// Copyright (c) 2024 Velvary Pty Ltd
// All rights reserved.
//
// This script is part of the Velvary bash scripts library.
//
// Licensed under the End User License Agreement (eula.txt) provided with this software.
//
// Author: Mark Pottie <mark@velvary.com.au>
// ---------------------------------------------------------------


function logToGoogleSheet($serviceAccountFile, $spreadsheetId, $data) {
    // Initialize the Google Client
    $client = new Google_Client();
    $client->setAuthConfig($serviceAccountFile);
    $client->addScope(Google_Service_Sheets::SPREADSHEETS);

    // Create the Google Sheets service
    $service = new Google_Service_Sheets($client);

    // get date at sydney time
    date_default_timezone_set('Australia/Sydney');
    // format date like "Mon, Aug 19, 2019"
    // get three values from the three arguments
    $date = date("D, M j, Y");
    $time = date("H:i");

    // if there is no sheet called RawLog, create it
    $sheets = $service->spreadsheets->get($spreadsheetId);
    $sheetNames = array_map(function($sheet) { return $sheet->properties->title; }, $sheets->sheets);
    if (!in_array('RawLog', $sheetNames)) {
        $requests = [
            new Google_Service_Sheets_Request([
                'addSheet' => [
                    'properties' => [
                        'title' => 'RawLog'
                    ]
                ]
            ])
        ];
        $batchUpdateRequest = new Google_Service_Sheets_BatchUpdateSpreadsheetRequest([
            'requests' => $requests
        ]);
        $service->spreadsheets->batchUpdate($spreadsheetId, $batchUpdateRequest);
        // add headers
        $values = [
            ['Date', 'Time', 'Client', 'Sub Client', 'Host Machine', 'Project', 'Ticket', 'Minutes Spent', 'Log Entry',]
        ];
        $range = 'RawLog!A1'; // Change to the desired range
        $headers = new Google_Service_Sheets_ValueRange([
            'values' => $values
        ]);
        $service->spreadsheets_values->append($spreadsheetId, $range, $headers, $params);
    } else {
        // if $data['logentry'] is empty, don't log it
        if (empty($data['logentry'])) {
            return;
        }
        $range = 'RawLog!A1:I'; // Change to the desired range
        $response = $service->spreadsheets_values->get($spreadsheetId, $range);
        $values = $response->getValues();
        $lastRow = end($values);
        $lastdate = $lastRow[0];
        $lasttime = $lastRow[1];
        // calculate the minutes since $lastdate $lasttime

        // Combine the date and time strings
        $datetimeString = $lastdate . ' ' . $lasttime;
        // Create a DateTime object from the custom format
        $datetime1 = DateTime::createFromFormat('D, M j, Y H:i', $datetimeString);
        $now = DateTime::createFromFormat('D, M j, Y H:i', $date . ' ' . $time);
        if (!$now) {
            echo "Error parsing current date and time: $date $time\n";
            return;
        }
        if ($datetime1) {
            $interval = $datetime1->diff($now);
            // minutes is the total number of minutes between the two dates
            $minutes = $interval->days * 24 * 60;
            $minutes += $interval->h * 60;
            $minutes += $interval->i;

            // if it seems like yesterday or something, set minutes to -1
            if ($interval->h > 6) {
                $minutes = 10;
            }

            echo "Minutes since last log entry: $minutes\n";          
        }


        if ($data['logentry'] == 'stop' && $lastRow['logentry'] != 'stop') {
            $data['minutes'] = $minutes;
            $data['client'] = $lastRow[2];
            $data['subclient'] = $lastRow[3];
            $data['hostmachine'] = $lastRow[4];
            $data['project'] = $lastRow[5];
            $data['ticket'] = $lastRow[6];
            $data['minutes'] = $minutes;
            $data['logentry'] = 'stop';
        } else if($data['minutes']=='c'){
            $data['minutes'] = $minutes;
            $data['client'] = $lastRow[2];
            $data['subclient'] = $lastRow[3];
            $data['hostmachine'] = $lastRow[4];
            $data['project'] = $lastRow[5];
            $data['ticket'] = $lastRow[6];
        } else if ($data['minutes'] == '' || $data['minutes'] == '?') {
            $data['minutes'] = $minutes;
        }
        // if $data['minutes'] is not a number, make it empty
        // if $data['minutes'] is not a number, make it empty
        if (!is_numeric($data['minutes'])) {
            $data['minutes'] = '';
        }
    }
    // Convert semicolon-separated commit messages back to multiline
    // for better readability in Google Sheets
    $logentry = $data['logentry'];
    if (strpos($logentry, '; ') !== false) {
        $logentry = str_replace('; ', "\n", $logentry);
    }
    
    // Append a row to the Google Sheet
    $values = [
        [$date, $time, $data['client'], $data['subclient'], $data['hostmachine'], $data['project'], $data['ticket'], intval($data['minutes']), $logentry]
    ];
    // echo "Appending $values to $spreadsheetId\n";
    $params = [
        'valueInputOption' => 'RAW'
    ];

    $body = new Google_Service_Sheets_ValueRange([
        'values' => $values
    ]);

    $range = 'RawLog!A1'; // Change to the desired range

    $result = $service->spreadsheets_values->append($spreadsheetId, $range, $body, $params);
    return;
}

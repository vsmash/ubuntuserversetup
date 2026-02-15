<?php
// Wrapper script for server devlog
// Calls logToGoogleSheet function with proper arguments

require_once(__DIR__ . '/bootstrap.php');

$data = [
    'client' => $argv[3],
    'subclient' => $argv[4],
    'hostmachine' => $argv[5],
    'project' => $argv[6],
    'ticket' => $argv[7],
    'minutes' => $argv[8],
    'logentry' => $argv[9]
];

$result = logToGoogleSheet($argv[1], $argv[2], $data);
echo $result;

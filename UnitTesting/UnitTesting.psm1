<#
Functions to assist with unit testing and code coverage analysis of .net projects.
Copyright (C) Simon Bridewell. All rights reserved.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see https://www.gnu.org/licenses/.
#>

# If your $env:PSModulePath environment variable includes the location of this module file then it will be automatically imported into your PS session.
# If you make changes to this file, run the following commands in order for them to take effect:
#   Remove-Module UnitTesting; Import-Module UnitTesting;

<#
.SYNOPSIS
    Runs the unit tests in one or more project and then performs code coverage analysis.

.DESCRIPTION
    Runs the unit tests in one or more project and then performs code coverage analysis.

.PARAMETER filterString
    If supplied then only the unit tests which match the filter string will be run.
    This parameter is passed as the --filter FullyQualifiedName parameter on the dotnet test command line.
    If not supplied then all unit tests in the project(s) will be run.

.PARAMETER listTests
    True to list names of each unit test instead of executing them.
    False to execute the tests.

.PARAMETER interactive
    If true then a dialogue box is displayed to the user inviting them to select from the discovered unit test projects.
    If false or not supplied then no dialogue box is displayed and all discovered unit test projects will be run.

.PARAMETER testProjectNameFilter
    Filter to identify unit test project filenames.
    Defaults to ".Test.csproj" if not supplied.

.PARAMETER listTestResults
    True to list the name and outcome of each test which was run.
#>
function Invoke-UnitTestsWithCodeAnalysis {
    param (
        [Parameter(Mandatory=$false)][string]$filterString,
        [Parameter(Mandatory=$false)][bool]$listTests,
        [Parameter(Mandatory=$false)][bool]$interactive,
        [Parameter(Mandatory=$false)][string]$testProjectNameFilter,
        [Parameter(Mandatory=$false)][switch]$listTestResults
    )

    Write-Output "Invoke-UnitTests starting";
    if ([System.String]::IsNullOrWhiteSpace($testProjectNameFilter)) {
        $testProjectNameFilter = ".Test.csproj";
    }

    $projectsToRun = Get-UnitTestProject -interactive $interactive -projectNameFilter $testProjectNameFilter;
    $projectsToRun | ForEach-Object {
        $testProjectName = $_.Name;
        $testProjectFolder = $_.Directory.FullName;
        $testProjectFullPath = $_.FullName;
        $assemblyUnderTest = $testProjectName.Replace($testProjectNameFilter, "");

        Remove-PreviousCodeCoverageResult -testProjectFolder $testProjectFolder;
        Invoke-DotnetTest -absoluteTestProjectPath $testProjectFullPath -filterString $filterString -collectCodeCoverage -listTests $listTests;
        if ($listTestResults) {
            Get-UnitTestResult;
        }

        Copy-CodeCoverageResultsToProjectFolder -testProjectFolder $testProjectFolder;
        Invoke-ReportGenerator -testProjectFolder $testProjectFolder -testProjectName $testProjectName -assemblyUnderTest $assemblyUnderTest;
    }

    Write-Output "Invoke-UnitTests finished";
}

<#
.SYNOPSIS
    Gets the unit test projects within the current folder and subfolders.

.DESCRIPTION
    Gets the unit test projects within the current folder and subfolders.

.PARAMETER projectNameFilter
    Filter to identify unit test project filenames.
    Defaults to ".Test.csproj" if not supplied.

.PARAMETER foldersToIngore
    Folders to skip when looking for unit test project files (e.g. build output folders).
    Defaults to "bin,obj" if not supplied.

.PARAMETER interactive
    If true then a dialogue box is displayed to the user inviting them to select from the discovered unit test projects.
    If false then no dialogue box is displayed and all discovered unit test projects will be run.
#>
function Get-UnitTestProject {
    param (
        [Parameter(Mandatory=$false)][string]$projectNameFilter,
        [Parameter(Mandatory=$false)][string]$foldersToIgnore,
        [Parameter(Mandatory=$false)][bool]$interactive
    )

    if ([System.String]::IsNullOrWhiteSpace($projectNameFilter)) {
        $projectNameFilter = ".Test.csproj";
    }

    if ([System.String]::IsNullOrWhiteSpace($foldersToIgnore)) {
        $foldersToIgnore = "bin,obj";
    }

    $testProjects = Get-ChildItem -Recurse | Where-Object Name -NE $foldersToIgnore | Where-Object Name -Like "*$projectNameFilter";
    if ($interactive) {
        $testProjects = $testProjects | Out-GridView -PassThru -Title "Select test projects to run";
    }

    $testProjects;
}

<#
.SYNOPSIS
    Deletes the results of a previous code coverage run from a project.

.DESCRIPTION
    Deletes the coverage.opencover.xml file from a previous code coverate run from the unit test project folder.
    There's only one file, but it's in a folder with a name which is unknown at design time.

.PARAMETER testProjectFolder
    Fully qualified path to the folder containing the unit test project.
#>
function Remove-PreviousCodeCoverageResult {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)][string]$testProjectFolder
    )

    $resultsToDelete = [System.IO.Path]::Combine($testProjectFolder, "TestResults");
    if ([System.IO.Directory]::Exists($resultsToDelete)) {
        Write-Output "Deleting $resultsToDelete";
        Remove-Item -Path $resultsToDelete -Recurse
    }
}

<#
.SYNOPSIS
    Runs a dotnet test command.

.DESCRIPTION
    Runs the unit tests in the supplied unit test project which match the supplied filter string.

.PARAMETER absoluteProjectPath
    Fully qualified path to the project file containing the unit tests.

.PARAMETER filterString
    If supplied then only the unit tests which match the filter string will be run.
    This parameter is passed as the --filter FullyQualifiedName parameter on the dotnet test command line.
    If not supplied then all unit tests in the project will be run.

.PARAMETER configuration
    If supplied then this parameter is passeed as the --configuration parameter on the dotnet test command line.
    If not supplied then a Debug configuration will be used.

.PARAMETER collectCodeCoverate
    True (or omitted) to build an OpenCover XML file containing code coverage.
    False to skip code coverage.

.PARAMETER listTests
    True to list the names of the test cases matching the filter instead of executing them.
    False (or omitted) to execute the test cases.
#>
function Invoke-DotnetTest {
    param (
        [Parameter(Mandatory=$true)][string]$absoluteTestProjectPath,
        [Parameter(Mandatory=$false)][string]$filterString,
        [Parameter(Mandatory=$false)][string]$configuration,
        [Parameter(Mandatory=$false)][switch]$collectCodeCoverage,
        [Parameter(Mandatory=$false)][bool]$listTests
    )

    $argumentArray = @($absoluteTestProjectPath, "--logger", "trx;LogFileName=DotNetTestLog.trx");
    if ($listTests) {
        $argumentArray += "--list-tests";
    }

    if (![System.String]::IsNullOrWhiteSpace($configuration)) {
        $argumentArray += "--configuration", $configuration;
    }

    if (![System.String]::IsNullOrWhiteSpace($filterString)) {
        $argumentArray += "--filter", "FullyQualifiedName~$filterString";
    }

    if ($listTests) {
        $argumentArray += "--list-tests";
    }

    if ($collectCodeCoverage) {
        $argumentArray += '--collect:"XPlat Code Coverage"';
        $argumentArray += "--", "DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover";
    }

    dotnet test @argumentArray @argumentHashTable
}

<#
.SYNOPSIS
    Reads the unit test results file and displays the name and outcome of each test.

.DESCRIPTION
    Reads the unit test results file and displays the name and outcome of each test.

.PARAMETER relativePathToTestResults
    Relative path from the project folder to the test results file.
    If not supplied, defaults to TestResults\DotNetTestLog.trx.
#>
function Get-UnitTestResult {
    param (
        [Parameter(Mandatory=$false)][string]$relativePathToTestResults
    )

    if ([System.String]::IsNullOrWhitespace($relativePathToTestResults)) {
        $relativePathToTestResults = "TestResults\DotNetTestLog.trx";
    }

    $trxContent = [xml](Get-Content $relativePathToTestResults);
    $results = $trxContent.TestRun.Results.UnitTestResult;
    $results | Select-Object -Property outcome,testName;
}

<#
.SYNOPSIS
    Copies the code coverage results file to the unit test project folder.

.DESCRIPTION
    Copies the code coverage results file to the unit test project folder.

.PARAMETER testProjectFolder
    Path to the root folder of the unit test project.

.PARAMETER codeCoverageResultsFileName
    Name of the code coverage results file.
#>
function Copy-CodeCoverageResultsToProjectFolder {
    param (
        [Parameter(Mandatory=$true)][string]$testProjectFolder,
        [Parameter(Mandatory=$false)][string]$codeCoverageResultsFileName
    )

    if ([System.String]::IsNullOrWhiteSpace($codeCoverageResultsFileName)) {
        $codeCoverageResultsFileName = "coverage.opencover.xml";
    }

    $testResultsFolder = [System.IO.Path]::Combine($testProjectFolder, "TestResults");
    $coverageFile = Get-ChildItem -Path $testResultsFolder -Recurse -Filter $codeCoverageResultsFileName;
    $finalCoverageFile = [System.IO.Path]::Combine($testProjectFolder, $codeCoverageResultsFileName);
    $coverageFile | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $finalCoverageFile;
    }
}

<#
.SYNOPSIS
    Uses reportgenerator.exe to build a HTML report of code coverage of unit tests.

.DESCRIPTION
    Uses reportgenerator.exe to build a HTML report of code coverage of unit tests.

.PARAMETER testProjectFolder
    Fully qualified path to the folder containing the unit test project.

.PARAMETER testProjectName
    The name of the project file containing the unit tests.

.PARAMETER assemblyUnderTest
    Name of the assembly being tested by the unit tests.

.PARAMETER coverageXmlFilename
    Filename of the file containing the code coverage report created by dotnet test.
    Defaults to coverage.opencover.xml if not supplied.

.PARAMETER reportGeneratorPath
    Fully qualified path to reportgenerator.exe.
    Defaults to where it exists on my laptop if not supplied (which might not be where it is for you).
#>
function Invoke-ReportGenerator {
    param (
        [Parameter(Mandatory=$true)][string]$testProjectFolder,
        [Parameter(Mandatory=$true)][string]$testProjectName,
        [Parameter(Mandatory=$true)][string]$assemblyUnderTest,
        [Parameter(Mandatory=$false)][string]$coverageXmlFilename,
        [Parameter(Mandatory=$false)][string]$reportGeneratorPath
    )

    if ([System.String]::IsNullOrWhiteSpace($coverageXmlFilename)) {
        $coverageXmlFilename = "coverage.opencover.xml";
    }

    $absoluteOutputPath = [System.IO.Path]::Combine($testProjectFolder, "CodeCoverage");
    $absoluteInputPath = [System.IO.Path]::Combine($testProjectFolder, $coverageXmlFilename);
    $argumentArray = @(
        "-reports:$absoluteInputPath",
        "-targetDir:$absoluteOutputPath",
        "-title:$testProjectName",
        "-assemblyFilters:$assemblyUnderTest"
    );
    if ([System.String]::IsNullOrWhiteSpace($reportGeneratorPath)) {
        $reportGeneratorPath = "$env:USERPROFILE\.nuget\packages\reportgenerator\5.2.4\tools\net6.0\reportgenerator.exe ";
    }

    # $reportGeneratorCommand = $reportGeneratorPath + '"-reports:$absoluteInputPath" "-targetDir:$absoluteOutputPath" "-title:$testProjectName" "-assemblyFilters:+*$assemblyUnderTest"'
    $reportGeneratorCommand = "$reportGeneratorPath @argumentArray";
    Invoke-Expression $reportGeneratorCommand;
}
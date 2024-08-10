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

.PARAMETER FilterString
    If supplied then only the unit tests which match the filter string will be run.
    This parameter is passed as the --filter FullyQualifiedName parameter on the dotnet test command line.
    If not supplied then all unit tests in the project(s) will be run.

.PARAMETER ListTests
    True to list names of each unit test instead of executing them.
    False to execute the tests.

.PARAMETER Interactive
    If true then a dialogue box is displayed to the user inviting them to select from the discovered unit test projects.
    If false or not supplied then no dialogue box is displayed and all discovered unit test projects will be run.

.PARAMETER TestProjectNameFilter
    Filter to identify unit test project filenames.
    Defaults to ".Test.csproj" if not supplied.

.PARAMETER ListTestResults
    True to list the name and outcome of each test which was run.
#>
function Invoke-UnitTestsWithCodeAnalysis {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$FilterString,
        [Parameter(Mandatory=$false)][bool]$ListTests,
        [Parameter(Mandatory=$false)][bool]$Interactive,
        [Parameter(Mandatory=$false)][string]$TestProjectNameFilter,
        [Parameter(Mandatory=$false)][switch]$ListTestResults
    )

    Write-Verbose "Invoke-UnitTestsWithCodeAnalysis starting";
    Write-Verbose "    (parameter) FilterString: $FilterString";
    Write-Verbose "    (parameter) ListTests: $ListTests";
    Write-Verbose "    (parameter) Interactive: $Interactive";
    Write-Verbose "    (parameter) TestProjectNameFilter: $TestProjectNameFilter";
    Write-Verbose "    (parameter) ListTestResults: $ListTestResults";

    if ([System.String]::IsNullOrWhiteSpace($TestProjectNameFilter)) {
        $TestProjectNameFilter = ".Test";
        Write-Verbose "TestprojectNameFilter is now $TestProjectNameFilter";
    }

    $projectsToRun = Get-UnitTestProject -interactive $Interactive -projectNameFilter $TestProjectNameFilter;
    $projectsToRun | ForEach-Object {
        Write-Verbose "Projects to test: $_";
        $testProjectName = $_.Name;
        $testProjectFolder = $_.Directory.FullName;
        $testProjectFullPath = $_.FullName;
        Write-Verbose "Reading content of test project $testProjectFullPath";
        $testProjectContent = [xml](Get-Content $testProjectFullPath);
        $testProjectAssemblyName = $testProjectContent.GetElementsByTagName("AssemblyName")[0].InnerText;
        $assemblyUnderTest = $testProjectAssemblyName.Replace($TestProjectNameFilter, "");

        Remove-PreviousCodeCoverageResult -TestProjectFolder $TestProjectFolder;
        Invoke-DotnetTest -AbsoluteTestProjectPath $TestProjectFullPath -FilterString $FilterString -CollectCodeCoverage -ListTests $ListTests;
        if ($ListTestResults) {
            Get-UnitTestResult;
        }

        Copy-CodeCoverageResultsToProjectFolder -TestProjectFolder $TestProjectFolder;
        Invoke-ReportGenerator -TestProjectFolder $TestProjectFolder -TestProjectName $TestProjectName -AssemblyUnderTest $assemblyUnderTest;
    }

    Write-Verbose "Invoke-UnitTestsWithCodeAnalysis finished";
}

<#
.SYNOPSIS
    Gets the unit test projects within the current folder and subfolders.

.DESCRIPTION
    Gets the unit test projects within the current folder and subfolders.

.PARAMETER ProjectNameFilter
    Filter to identify unit test project filenames.
    Defaults to ".Test.csproj" if not supplied.

.PARAMETER FoldersToIngore
    Folders to skip when looking for unit test project files (e.g. build output folders).
    Defaults to "bin,obj" if not supplied.

.PARAMETER Interactive
    If true then a dialogue box is displayed to the user inviting them to select from the discovered unit test projects.
    If false then no dialogue box is displayed and all discovered unit test projects will be run.
#>
function Get-UnitTestProject {
    param (
        [Parameter(Mandatory=$false)][string]$ProjectNameFilter,
        [Parameter(Mandatory=$false)][string]$FoldersToIgnore,
        [Parameter(Mandatory=$false)][bool]$Interactive
    )

    Write-Verbose "Get-UnitTestProject starting";
    Write-Verbose "    (parameter) ProjectNameFilter: $ProjectNameFilter";
    Write-Verbose "    (parameter) FoldersToIgnore: $FoldersToIgnore";
    Write-Verbose "    (parameter) Interactive: $Interactive";

    if ([System.String]::IsNullOrWhiteSpace($ProjectNameFilter)) {
        $ProjectNameFilter = ".Test.csproj";
        Write-Verbose "ProjectNameFilter is now $ProjectNameFilter";
    }

    if ([System.String]::IsNullOrWhiteSpace($FoldersToIgnore)) {
        $foldersToIgnore = "bin,obj";
        Write-Verbose "FoldersToIgnore is now $FoldersToIgnore";
    }

    $testProjects = Get-ChildItem -Recurse | Where-Object Name -NE $FoldersToIgnore | Where-Object Name -Like "*$ProjectNameFilter.csproj";
    Write-Verbose "testProjects: $testProjects";
    if ($Interactive) {
        $testProjects = $testProjects | Out-GridView -PassThru -Title "Select test projects to run";
        Write-Verbose "testProjects is now $testProjects";
    }

    $testProjects; # return value
    Write-Verbose "Get-UnitTestProject finished";
}

<#
.SYNOPSIS
    Deletes the results of a previous code coverage run from a project.

.DESCRIPTION
    Deletes the coverage.opencover.xml file from a previous code coverate run from the unit test project folder.
    There's only one file, but it's in a folder with a name which is unknown at design time.

.PARAMETER TestProjectFolder
    Fully qualified path to the folder containing the unit test project.
#>
function Remove-PreviousCodeCoverageResult {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)][string]$TestProjectFolder
    )

    Write-Verbose "Remove-PreviousCodeCoverageResult starting";
    Write-Verbose "    (parameter) TestProjectFolder: $TestProjectFolder";

    $resultsToDelete = [System.IO.Path]::Combine($TestProjectFolder, "TestResults");
    if ([System.IO.Directory]::Exists($resultsToDelete)) {
        Write-Output "Deleting previous test results from $resultsToDelete";
        Remove-Item -Path $resultsToDelete -Recurse
    }

    Write-Verbose "Remove-PreviousCodeCoverageResult finished";
}

<#
.SYNOPSIS
    Runs a dotnet test command.

.DESCRIPTION
    Runs the unit tests in the supplied unit test project which match the supplied filter string.

.PARAMETER AbsoluteProjectPath
    Fully qualified path to the project file containing the unit tests.

.PARAMETER FilterString
    If supplied then only the unit tests which match the filter string will be run.
    This parameter is passed as the --filter FullyQualifiedName parameter on the dotnet test command line.
    If not supplied then all unit tests in the project will be run.

.PARAMETER Configuration
    If supplied then this parameter is passeed as the --configuration parameter on the dotnet test command line.
    If not supplied then a Debug configuration will be used.

.PARAMETER CollectCodeCoverage
    True (or omitted) to build an OpenCover XML file containing code coverage.
    False to skip code coverage.

.PARAMETER ListTests
    True to list the names of the test cases matching the filter instead of executing them.
    False (or omitted) to execute the test cases.
#>
function Invoke-DotnetTest {
    param (
        [Parameter(Mandatory=$true)][string]$AbsoluteTestProjectPath,
        [Parameter(Mandatory=$false)][string]$FilterString,
        [Parameter(Mandatory=$false)][string]$Configuration,
        [Parameter(Mandatory=$false)][switch]$CollectCodeCoverage,
        [Parameter(Mandatory=$false)][bool]$ListTests
    )

    Write-Verbose "Invoke-DotnetTest starting";
    Write-Verbose "    (parameter) AbsoluteTestProjectPath: $AbsoluteProjectPath";
    Write-Verbose "    (parameter) FilterString: $FilterString";
    Write-Verbose "    (parameter) Configuration: $Configuration";
    Write-Verbose "    (parameter) CollectCodeCoverage: $CollectCodeCoverage";
    Write-Verbose "    (parameter) ListTests: $ListTests";

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

    Write-Verbose "Argument array for dotnet test command: $argumentArray";
    dotnet test @argumentArray
    Write-Verbose "Invoke-DotnetTest finished";
}

<#
.SYNOPSIS
    Reads the unit test results file and displays the name and outcome of each test.

.DESCRIPTION
    Reads the unit test results file and displays the name and outcome of each test.

.PARAMETER RelativePathToTestResults
    Relative path from the project folder to the test results file.
    If not supplied, defaults to TestResults\DotNetTestLog.trx.
#>
function Get-UnitTestResult {
    param (
        [Parameter(Mandatory=$false)][string]$RelativePathToTestResults
    )

    Write-Verbose "Get-UnitTestResult starting";
    Write-Verbose "    (parameter) RelativePathToTestResults: $RelativePathToTestResults";

    if ([System.String]::IsNullOrWhitespace($relativePathToTestResults)) {
        $relativePathToTestResults = "TestResults\DotNetTestLog.trx";
        Write-Verbose "RelativePathToTestResults is now $RelativePathToTestResults";
    }

    $trxContent = [xml](Get-Content $relativePathToTestResults);
    $results = $trxContent.TestRun.Results.UnitTestResult;
    $results | Select-Object -Property outcome,testName;
    Write-Verbose "Get-UnitTestResult finished";
}

<#
.SYNOPSIS
    Copies the code coverage results file to the unit test project folder.

.DESCRIPTION
    Copies the code coverage results file to the unit test project folder.

.PARAMETER TestProjectFolder
    Path to the root folder of the unit test project.

.PARAMETER CodeCoverageResultsFileName
    Name of the code coverage results file.
#>
function Copy-CodeCoverageResultsToProjectFolder {
    param (
        [Parameter(Mandatory=$true)][string]$TestProjectFolder,
        [Parameter(Mandatory=$false)][string]$CodeCoverageResultsFileName
    )

    Write-Verbose "Copy-CodeCoverageResultsToProjectFolder starting";
    Write-Verbose "    (parameter) TestProjectFolder: $TestProjectFolder";
    Write-Verbose "    (parameter) CodeCoverageResultsFileName: $CodeCoverageResultsFileName";

    if ([System.String]::IsNullOrWhiteSpace($CodeCoverageResultsFileName)) {
        $CodeCoverageResultsFileName = "coverage.opencover.xml";
        Write-Verbose "CodeCoverageResultsFileName is now $CodeCoverageResultsFileName";
    }

    $testResultsFolder = [System.IO.Path]::Combine($testProjectFolder, "TestResults");
    $coverageFile = Get-ChildItem -Path $testResultsFolder -Recurse -Filter $codeCoverageResultsFileName;
    $finalCoverageFile = [System.IO.Path]::Combine($testProjectFolder, $codeCoverageResultsFileName);
    $coverageFile | ForEach-Object {
        Write-Output "Copying $_ to $finalCoverageFile";
        Copy-Item -Path $_.FullName -Destination $finalCoverageFile;
    }

    Write-Verbose "Copy-CodeCoverageResultsToProjectFolder finished";
}

<#
.SYNOPSIS
    Uses reportgenerator.exe to build a HTML report of code coverage of unit tests.

.DESCRIPTION
    Uses reportgenerator.exe to build a HTML report of code coverage of unit tests.

.PARAMETER testProjectFolder
    Fully qualified path to the folder containing the unit test project.

.PARAMETER TestProjectName
    The name of the project file containing the unit tests.

.PARAMETER AssemblyUnderTest
    Name of the assembly being tested by the unit tests.

.PARAMETER CoverageXmlFilename
    Filename of the file containing the code coverage report created by dotnet test.
    Defaults to coverage.opencover.xml if not supplied.

.PARAMETER ReportGeneratorPath
    Fully qualified path to reportgenerator.exe.
    Defaults to where it exists on my laptop if not supplied (which might not be where it is for you).
#>
function Invoke-ReportGenerator {
    param (
        [Parameter(Mandatory=$true)][string]$TestProjectFolder,
        [Parameter(Mandatory=$true)][string]$TestProjectName,
        [Parameter(Mandatory=$true)][string]$AssemblyUnderTest,
        [Parameter(Mandatory=$false)][string]$CoverageXmlFilename,
        [Parameter(Mandatory=$false)][string]$ReportGeneratorPath
    )

    Write-Verbose "Invoke-ReportGenerator starting";
    Write-Verbose "    (parameter) TestProjectFolder: $TestProjectFolder";
    Write-Verbose "    (parameter) TestProjectName: $TestProjectName";
    Write-Verbose "    (parameter) AssemblyUnderTest: $AssemblyUnderTest";
    Write-Verbose "    (parameter) CoverageXmlFilename: $CoverageXmlFilename";
    Write-Verbose "    (parameter) ReportGeneratorPath: $ReportGeneratorPath";

    if ([System.String]::IsNullOrWhiteSpace($CoverageXmlFilename)) {
        $CoverageXmlFilename = "coverage.opencover.xml";
        Write-Verbose "CoverageXmlFilename is now $CoverageXmlFilename";
    }

    $absoluteOutputPath = [System.IO.Path]::Combine($testProjectFolder, "CodeCoverage");
    $absoluteInputPath = [System.IO.Path]::Combine($testProjectFolder, $coverageXmlFilename);
    $argumentArray = @(
        "-reports:$absoluteInputPath",
        "-targetDir:$absoluteOutputPath",
        "-title:$testProjectName",
        "-assemblyFilters:+$assemblyUnderTest"
    );
    if ([System.String]::IsNullOrWhiteSpace($reportGeneratorPath)) {
        $reportGeneratorPath = "$env:USERPROFILE\.nuget\packages\reportgenerator\5.2.4\tools\net6.0\reportgenerator.exe ";
        Write-Verbose "ReportGeneratorPath is now $ReportGeneratorPath";
    }

    Write-Verbose "Argument array for reportgenerator command: $argumentArray";
    & $reportGeneratorPath @argumentArray -ErrorAction Stop
    Write-Verbose "Invoke-ReportGenerator finished";
}
# PSBruteEvaluation

Wrapper around [PSBrute](https://github.com/MatejKafka/FEL-PSBrute), simplifying student assignment evaluation.

## Usage

First, open the `BRUTE_Evaluation.psm1` file and **set the course page and parallel names** at the top of the file.

Next, import the module by calling `Import-Module BRUTE_Evaluation` (auto-import works as usual, but when imported manually, a nice table for each parallel is printed).

To start evaluation, call `brutes <assignment_name> <student_username>` ("BRUTE start"), tab completion should work for both parameters. This will download the student submission to a temporary directory and open it in a file explorer.

Next, run `brutee` ("BRUTE end"), passing it the evaluation parameters (use autocomplete to view the supported parameters).

## Installation

Clone this repository to a directory that's in your `$env:PSModulePath`. Note that the cloned directory **must be called `BRUTE_Evaluation`**, which is also the module's name.

```
git clone https://github.com/MatejKafka/FEL-PSBrute BRUTE
git clone https://github.com/MatejKafka/FEL-PSBruteEvaluation BRUTE_Evaluation
```

Now, the module should be importable by calling `Import-Module BRUTE_Evaluation`, or just invoking one of the exported functions.

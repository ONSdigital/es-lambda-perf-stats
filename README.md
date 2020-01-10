Scripts to generate performance stats for lambda invocations on AWS.

These are meant to be run in a *Nix environment. These scripts may run in Git Bash or Cygwin, but they have not been tested on these.

### Pre-requisites
AWS CLI setup

JQ

Unix Utils (grep, awk, sed, paste, sort)

### Minimal Usage
    
```
./exec-lambda-analysis.sh -f lambda_func_name_or_complete_arn
```
    
### Complete Usage

```
./exec-lambda-analysis.sh -h
            f) # Specify Lambda Function Name (complete ARN or just name)
            m) # OPTIONAL. Specify Memory to update the Lambda to. **Defaults to 256 MB**
            i) # OPTIONAL. Specify Number of invocations to be done. **Defaults to 5**
            r) # OPTIONAL. Specify AWS region. **Defaults to London (eu-west-2)**
            p) # OPTIONAL. Specify XRay Pause Time. **Defaults to 5 seconds**
```

### Focussing on Cold Starts

The memory parameter accepts a comma separated list of values making the following possible:

```
./exec-lambda-analysis.sh -f lambda_function_name -m "128,256" -i 4 -r eu-west-2
```

The above would result in lambda_function_name being invoked 4 times with the Lambda being updated
to use the following memory assignments:

| Invocation Number | Memory Assigned To Lambda (MB) |
|:------------------|:-------------------------------|
| 1                 | 128                            |
| 2                 | 256                            |
| 3                 | 128                            |
| 4                 | 256                            |

Since with a list of memories the memory assignment will always be
changed, this will result in forced cold starts for *every invocation*


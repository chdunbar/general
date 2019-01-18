**sdsDeployer.ps1**

Run it with '.\sdsDeployer.ps1' in Powershell. 

The script has comments that give more detail, but basically you provide some deployment parameters and then run it. It should be fairly easy to modify as well.

This should make the authoring/testing flow a little easier. We can deploy custom and prod solutions without needing to go to the **My Solutions** section in https://sds.azureiotsolutions.com/en-US/CustomSolutions. Also we can start a bunch of deployments at the same time (vs opening a bunch of tabs).

For single deployments it monitors/prints updates on each step and timestamps. Then gives a total deployment time at the end of the whole thing. Single deployments support up to a single manual step. The comments of the script detail how to provide the manual inputs.

For multiple deployments it will just append a 0...n to the end of the solutionName each time. But it only starts them, right now any solutions with manual steps do not benefit from this. They would all be created but then await action on the manual step. Which is still kind of nice.

Variants are supported in both.

The script could still be improved though. Feel free to change it.

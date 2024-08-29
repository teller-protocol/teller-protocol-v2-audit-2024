import { DeployFunction } from 'hardhat-deploy/dist/types'

const deployFn: DeployFunction = async (hre) => {
  hre.log('----------')
  hre.log('')
  hre.log('CollateralManager: Proposing upgrade...')

  const collateralManager = await hre.contracts.get('CollateralManager')
 
  await hre.upgrades.proposeBatchTimelock({
    title: 'CollateralManager: Add Dust Withdrawl',
    description: ` 
# TellerV2

* Adds support for necessary functions for Lender Commitment Groups.
`,
    _steps: [
      {
        proxy: collateralManager,
        implFactory: await hre.ethers.getContractFactory('CollateralManager' ),

        opts: {
          unsafeAllow: [
            'constructor',
            'state-variable-immutable',
            'external-library-linking',
          ],
          constructorArgs: [ ],
        },
      },
    ],
  })

  hre.log('done.')
  hre.log('')
  hre.log('----------')

  return true
}

// tags and deployment
deployFn.id = 'collateral-manager:dust-upgrade'
deployFn.tags = [
  'proposal',
  'upgrade',
  'collateral-manager',
  'collateral-manager:dust-upgrade',
]
deployFn.dependencies = ['collateral:manager:deploy']
deployFn.skip = async (hre) => {
  return !hre.network.live || !['sepolia', 'polygon'].includes(hre.network.name)
}
export default deployFn

import { DeployFunction } from 'hardhat-deploy/dist/types'

const deployFn: DeployFunction = async (hre) => {
  hre.log('----------')
  hre.log('')
  hre.log('LenderCommitmentForwarder: Proposing upgrade...')

  const tellerV2 = await hre.contracts.get('TellerV2')
  const marketRegistry = await hre.contracts.get('MarketRegistry')
  const lenderCommitmentForwarder = await hre.contracts.get(
    'LenderCommitmentForwarder'
  )

  await hre.defender.proposeBatchTimelock(
    'Lender Commitment Forwarder Merkle Upgrade',
    ` 
 
# LenderCommitmentForwarder

* Adds two new collateral types, ERC721_MERKLE_PROOF and ERC1155_MERKLE_PROOF.
* Add a new function acceptCommitmentWithProof which is explicitly used with these new types.
* Merkle proofs can be used to create commitments for a set of tokenIds for an ERC721 or ERC1155 collection.
`,
    [
      {
        proxy: lenderCommitmentForwarder.address,
        implFactory: await hre.ethers.getContractFactory(
          'LenderCommitmentForwarder'
        ),

        opts: {
          unsafeAllow: ['constructor', 'state-variable-immutable'],
          constructorArgs: [tellerV2.address, marketRegistry.address],
        },
      },
    ]
  )

  hre.log('done.')
  hre.log('')
  hre.log('----------')

  return true
}

// tags and deployment
deployFn.id = 'lender-commitment-forwarder:merkle-upgrade'
deployFn.tags = [
  'proposal',
  'upgrade',
  'lender-commitment-forwarder',
  'lender-commitment-forwarder:merkle-upgrade',
]
deployFn.dependencies = [
  'market-registry:deploy',
  'teller-v2:deploy',
  'lender-commitment-forwarder:deploy',
]
deployFn.skip = async (hre) => {
  return false
}
export default deployFn
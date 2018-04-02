#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Build your first network (BYFN) end-to-end test"
echo
CHANNEL_NAME="$1"
CHANNEL_NAME2="$3"
DELAY="$2"
: ${CHANNEL_NAME:="mychannel123"}
: ${CHANNEL_NAME2:="mychannel12"}
: ${CHANNEL_NAME3:="mychannel13"}
: ${TIMEOUT:="10000"}
COUNTER=1
MAX_RETRY=5
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem



# verify the result of the end-to-end test
verifyResult () {
	if [ $1 -ne 0 ] ; then
		echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
    echo "========= ERROR !!! FAILED to execute End-2-End Scenario ==========="
		echo
   		exit 1
	fi
}

setGlobals () {

	if [ $1 -eq 0 ] ; then
		CORE_PEER_LOCALMSPID="Org1MSP"
		CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
		if [ $1 -eq 0 ]; then
			CORE_PEER_ADDRESS=peer0.org1.example.com:7051
			CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
		fi
	elif [ $1 -eq 1 ] ; then
		CORE_PEER_LOCALMSPID="Org2MSP"
		CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
		if [ $1 -eq 1 ]; then
			CORE_PEER_ADDRESS=peer0.org2.example.com:7051
		fi
	else
		CORE_PEER_LOCALMSPID="Org3MSP"
		CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt
		CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
		if [ $1 -eq 2 ]; then
			CORE_PEER_ADDRESS=peer0.org3.example.com:7051
		fi
	
        fi

	env |grep CORE
}

createChannel() {

	echo "Channel name : "$2
  setGlobals $1

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer channel create -o orderer.example.com:7050 -c $2 -f ./channel-artifacts/channel$2.tx >&log.txt
	else
		peer channel create -o orderer.example.com:7050 -c $2 -f ./channel-artifacts/channel$2.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Channel creation failed"
	echo "===================== Channel \"$2\" is created successfully ===================== "
	echo
}

updateAnchorPeers() {
  PEER=$1
  setGlobals $PEER

  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer channel update -o orderer.example.com:7050 -c $2 -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors$2.tx >&log.txt
	else
		peer channel update -o orderer.example.com:7050 -c $2 -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors$2.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Anchor peer update failed"
	echo "===================== Anchor peers for org \"$CORE_PEER_LOCALMSPID\" on \"$2\" is updated successfully ===================== "
	sleep $DELAY
	echo
}

## Sometimes Join takes time hence RETRY atleast for 5 times
joinWithRetry () {
	peer channel join -b $2.block  >&log.txt
	res=$?
	cat log.txt
	if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "PEER$1 failed to join the channel, Retry after 2 seconds"
		sleep $DELAY
		joinWithRetry $1 $2
	else
		COUNTER=1
	fi
  verifyResult $res "After $MAX_RETRY attempts, PEER$ch has failed to Join the Channel"
}

joinChannel () {

args=("$@")
NoOfArgs=${#args[@]}

	for (( i=1;i<$NoOfArgs;i++)); do
    		setGlobals ${args[${i}]}
 		joinWithRetry ${args[${i}]} $1
		echo "===================== PEER${args[${i}]} joined on the channel \"$1\" ===================== "
		sleep $DELAY
		echo
	done
}

installChaincode () {
	PEER=$1
	setGlobals $PEER
	peer chaincode install -n mycc$2 -v 1.0 -p github.com/hyperledger/fabric/examples/chaincode/go/$3 >&log.txt
	res=$?
	cat log.txt
        verifyResult $res "Chaincode installation on remote peer PEER$PEER has Failed"
	echo "===================== Chaincode is installed on remote peer PEER$PEER ===================== "
	echo
}

instantiateChaincode () {
	PEER=$1
	setGlobals $PEER
	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		if [ $2 == "mychannel123" ]; then
			peer chaincode instantiate -o orderer.example.com:7050 -C $2 -n mycc$2 -v 1.0 -c '{"Args":["init","a","'$3'","b","'$4'"]}' -P "OR	('Org1MSP.member','Org2MSP.member','Org3MSP.member')" >&log.txt
		elif [ $2 == "mychannel12" ]; then
                        peer chaincode instantiate -o orderer.example.com:7050 -C $2 -n mycc$2 -v 1.0 -c '{"Args":["init","a","'$3'","b","'$4'"]}' -P "OR       ('Org1MSP.member','Org2MSP.member')" >&log.txt
		else 
			peer chaincode instantiate -o orderer.example.com:7050 -C $2 -n mycc$2 -v 1.0 -c '{"Args":["init","a","'$3'","b","'$4'"]}' -P "OR       ('Org1MSP.member','Org3MSP.member')" >&log.txt
		fi

	else
		if [ $2 == "mychannel123" ]; then
			peer chaincode instantiate -o orderer.example.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $2 -n mycc$2 -v 1.0 -c '{"Args":["init","a","'$3'","b","'$4'"]}' -P "OR	('Org1MSP.member','Org2MSP.member','Org3MSP.member')" >&log.txt
		elif [ $2 == "mychannel12" ]; then
			peer chaincode instantiate -o orderer.example.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $2 -n mycc$2 -v 1.0 -c '{"Args":["init","a","'$3'","b","'$4'"]}' -P "OR     ('Org1MSP.member','Org2MSP.member')" >&log.txt
		else 
			peer chaincode instantiate -o orderer.example.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $2 -n mycc$2 -v 1.0 -c '{"Args":["init","a","'$3'","b","'$4'"]}' -P "OR     ('Org1MSP.member','Org3MSP.member')" >&log.txt
		fi

	fi
	res=$?
	cat log.txt
	verifyResult $res "Chaincode instantiation on PEER$PEER on channel '$2' failed"
	echo "===================== Chaincode Instantiation on PEER$PEER on channel '$2' is successful ===================== "
	echo
}

chaincodeQuery () {
  PEER=$1
  echo "===================== Querying on PEER$PEER on channel '$2'... ===================== "
  setGlobals $PEER
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
     sleep $DELAY
     echo "Attempting to Query PEER$PEER ...$(($(date +%s)-starttime)) secs"
     peer chaincode query -C $2 -n mycc$2 -c '{"Args":["query","a"]}' >&log.txt
     test $? -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
     test "$VALUE" = "$3" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0 ; then
	echo "===================== Query on PEER$PEER on channel '$2' is successful ===================== "
  else
	echo "!!!!!!!!!!!!!!! Query result on PEER$PEER is INVALID !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
	echo
	exit 1
  fi
}

chaincodeInvoke () {
	PEER=$1
	setGlobals $PEER
	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode invoke -o orderer.example.com:7050 -C $2 -n mycc$2 -c '{"Args":["invoke","a","b","'$3'"]}' >&log.txt
	else
		peer chaincode invoke -o orderer.example.com:7050  --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $2 -n mycc$2 -c '{"Args":["invoke","a","b","'$3'"]}' >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Invoke execution on PEER$PEER failed "
	echo "===================== Invoke transaction on PEER$PEER on channel '$2' is successful ===================== "
	echo
}



## Create channel1
echo "Creating channel1..."
createChannel 0 mychannel123 

## Join all the peers to the channel1
echo "Having all peers join the channel1..."
joinChannel mychannel123 0 1 2  

## Set the anchor peers for each org in the channel
echo "Updating anchor peers for org1..."
updateAnchorPeers 0 mychannel123 
echo "Updating anchor peers for org2..."
updateAnchorPeers 1 mychannel123
echo "Updating anchor peers for org3..."
updateAnchorPeers 2 mychannel123

## Install chaincode on Peer0/Org1 and Peer0/Org2
echo "Installing chaincode on org1/peer0..."
installChaincode 0 mychannel123 chaincode_example02
echo "Install chaincode on org2/peer0..."
installChaincode 1 mychannel123 chaincode_example02

#Instantiate chaincode on Peer0/Org2
echo "Instantiating chaincode on org2/peer0..."
instantiateChaincode 1 mychannel123 100 200

#Query on chaincode on Peer0/Org1
echo "Querying chaincode on org1/peer0..."
chaincodeQuery 0 mychannel123 100

#Invoke on chaincode on Peer0/Org1
echo "Sending invoke transaction on org1/peer0..."
chaincodeInvoke 0 mychannel123 10

## Install chaincode on Peer0/Org3
echo "Installing chaincode on org3/peer0..."
installChaincode 2 mychannel123 chaincode_example02

#Query on chaincode on Peer0/Org3, check if the result is 90
echo "Querying chaincode on org3/peer0..."
chaincodeQuery 2 mychannel123 90

## Create channel12
echo "Creating channel12..."
createChannel 0 mychannel12

## Join all the peers to the channel12
echo "Having all peers join the channel12..."
joinChannel mychannel12 0 1   

## Set the anchor peers for each org in the channel
echo "Updating anchor peers for org1..."
updateAnchorPeers 0 mychannel12
echo "Updating anchor peers for org2..."
updateAnchorPeers 1 mychannel12

## Install chaincode on Peer0/Org1 and Peer0/Org2
echo "Installing chaincode on org1/peer0..."
installChaincode 0 mychannel12 chaincode_example02
echo "Install chaincode on org2/peer0..."
installChaincode 1 mychannel12 chaincode_example02

#Instantiate chaincode on Peer0/Org2
echo "Instantiating chaincode on org2/peer0..."
instantiateChaincode 1 mychannel12 1000 2000

#Query on chaincode on Peer0/Org1
echo "Querying chaincode on org1/peer0..."
chaincodeQuery 0 mychannel12 1000

#Invoke on chaincode on Peer0/Org1
echo "Sending invoke transaction on org1/peer0..."
chaincodeInvoke 0 mychannel12 100

#Query on chaincode on Peer0/Org2, check if the result is 900
echo "Querying chaincode on org2/peer0..."
chaincodeQuery 1 mychannel12 900


## Create channel13
echo "Creating channel13..."
createChannel 0 mychannel13

## Join all the peers to the channel13
echo "Having all peers join the channel13..."
joinChannel mychannel13 0 2   

## Set the anchor peers for each org in the channel
echo "Updating anchor peers for org1..."
updateAnchorPeers 0 mychannel13
echo "Updating anchor peers for org3..."
updateAnchorPeers 2 mychannel13

## Install chaincode on Peer0/Org1 and Peer0/Org3
echo "Installing chaincode on org1/peer0..."
installChaincode 0 mychannel13 chaincode_example02
echo "Install chaincode on org3/peer0..."
installChaincode 2 mychannel13 chaincode_example02

#Instantiate chaincode on Peer0/Org3
echo "Instantiating chaincode on org3/peer0..."
instantiateChaincode 2 mychannel13 10000 20000

#Query on chaincode on Peer0/Org1
echo "Querying chaincode on org1/peer0..."
chaincodeQuery 0 mychannel13 10000

#Invoke on chaincode on Peer0/Org1
echo "Sending invoke transaction on org1/peer0..."
chaincodeInvoke 0 mychannel13 1000

#Query on chaincode on Peer0/Org3, check if the result is 9000
echo "Querying chaincode on org3/peer0..."
chaincodeQuery 2 mychannel13 9000

echo
echo "========= All GOOD, BYFN execution completed =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0

# Programmable network, second homework
This project creates a consensus system among multiple switches managed by kathara via the p4 language [topology](/shared/hw2_layout.png).  
Each switch will compile and run [consensus.p4](/shared/consensus.p4) to both manage the consensus algorithm and the IP forwarding. 

The technology supported by this projects are: 
- Ethernet
- IPv4
- IPv6
- TCP
- UDP

To manage consensus a "3.5 layer" consensus header is inserted (between IP and TCP/UDP). This header has a total size of 24 bits:
```
header consensus_t {
    bit<8> allow;
    bit<8> unallow;
    bit<8> protocol;
}
```
As defined by the assignment, we need the majority vote to allow the packet to the destination. This means that we can group the number of switches that don't vote and those that vote
negativly against those that vote positivly for a particular packet. The consensus header is added once to every packet as soon as it is seen by any switch running the p4 program
```
apply {
  // Add the consensus header if it doesn't exists
  if(!hdr.consensus.isValid()) consensus_ingress();

  ...
}
```
[consensus_ingress action](https://github.com/filwastaken/programmable_hw2/blob/9797e2387ffff7d6a58fd17dd72761d40da804bd/shared/consensus.p4?plain=1#L188).

This header is removed during the forwarding phase, in case the next hop is the destination host:

```
action ipv4_forward(bit<9> port, bit<1> lastSwitch) {
  if(lastSwitch){
    // Dropping packet in case it didn't pass the consensus!
    if(hdr.consensus.allow <= hdr.consensus.unallow) {
      mark_to_drop(standard_metadata);
      return ;
    }

    hdr.ipv4.protocol = hdr.consensus.protocol;
    hdr.consensus.setInvalid();
  }

  ...
```
This is the IPv4 code snippet, the full forwardings can be found at:
- [IPv4 forwarding](https://github.com/filwastaken/programmable_hw2/blob/9797e2387ffff7d6a58fd17dd72761d40da804bd/shared/consensus.p4?plain=1#L201)
- [IPv6 forwarding](https://github.com/filwastaken/programmable_hw2/blob/9797e2387ffff7d6a58fd17dd72761d40da804bd/shared/consensus.p4?plain=1#L217)

The possible actions for a switch are:
1 NoAction, which equals an abstention vote
2 consent,
3 unconsent.


# Switches definitions
Since all the switches require the forwarding functionality, we have defined static routes in the commands.txt to allow every packet to its destination. However, since the switches only
check one layer to cast their vote, we have not defined any table rules for the layers that shouldn't be looked at by a particular switch. Moreover, we have set the function NoAction as the
default for all the consensus tables.

Here follows an high level explanation of every tables and actions defined for each switch, defined in each switch's comamnds.txt:
## S1 rules


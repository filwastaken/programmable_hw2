/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

// NOTE: new type added here
const bit<8> TYPE_CONSENSUS = 253; // The IP header leaves 253 and 254 unassigned by default for testing purposes
const bit<16> TYPE_IPV4 = 0x0800;
const bit<16> TYPE_IPV6 = 0x86DD;
const bit<8> TYPE_UDP = 17;
const bit<8> TYPE_TCP = 6;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;

// Layer 2 headers
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

// Layer 3 headers
header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header ipv6_t {
    bit<4> version;
    bit<8> traffClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8> nextHeader;
    bit<8> hoplim;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

// Added consensus header type. It will be a 3.5 layer header
// I don't need to add an 'abstained' option. I only need to check wheter the 'allowed' votes are the majority (I can group 'unallowed' and 'abstained')
header consensus_t {
    bit<8> allow;
    bit<8> unallow;
    bit<8> protocol;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> sequenceNum;
    bit<32> ackNum;
    bit<4> dataOffset;
    bit<3> reserved;
    bit<9> flags;
    bit<16> winSize;
    bit<16> checksum;
    bit<16> urgentPointer;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> len;
    bit<16> checksum;
}

// Metadata
struct metadata {
    /* empty */
}

// Headers
struct headers {
    // Layer 2 headers
    ethernet_t ethernet;

    // Layer 3 headers
    ipv4_t ipv4;
    ipv6_t ipv6;

    // Layer 4 headers
    consensus_t consensus;
    udp_t udp;
    tcp_t tcp;
}

/*************************************************************************/
/**************************  P A R S E R  ********************************/
/*************************************************************************/

// TODO: Added the consensus parsing function in MyParser
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType){
            TYPE_IPV4: parse_ipv4;
            TYPE_IPV6: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv4{
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol){
            TYPE_CONSENSUS: parse_consensus;
            TYPE_TCP: parse_tcp;
            TYPE_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_ipv6{
        packet.extract(hdr.ipv6);
        transition select(hdr.ipv6.nextHeader){
            TYPE_CONSENSUS: parse_consensus;
            TYPE_TCP: parse_tcp;
            TYPE_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_consensus {
        packet.extract(hdr.consensus);
        transition accept;
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transistion accept;
    }
}

/*************************************************************************/
/**************  C H E C K S U M   V E R I F I C A T I O N  **************/
/*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************/
/*****************  I N G R E S S   P R O C E S S I N G  *****************/
/*************************************************************************/

control MyIngress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {

    action drop() {
        mark_to_drop(standard_metadata);
    }

    action ipv4_forward(bit<48> dstAddr, bit<9> port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    action ipv6_forward(bit<128> dstAddr, bit<9> port){
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv6.hoplim = hdr.ipv6.hoplim - 1;
    }

    action consensus_ingress(){
        hdr.consensus.setValid();

        if(hdr.ipv4.isValid()){
            hdr.consensus.protocol = hdr.ipv4.protocol;
            hdr.ipv4.protocol = TYPE_CONSENSUS;
        } else if(hdr.ipv6.isValid()) {
            hdr.consensus.protocol = hdr.ipv6.nextHeader;
            hdr.ipv6.protocol = TYPE_CONSENSUS;
        }
    }

    action consensus_egress(macAddr_t dstAddr, egressSpec_t port){
        // Dropping packet in case it didn't pass the consensus!
        if(hdr.consensus.allow <= hdr.consensus.unallow) {
            mark_to_drop(standard_metadata);
            return ;
        }

        standard_metadata.egress_spec = port;
        hdr.ethernet.dstAddr = dstAddr;
        if(hdr.ipv4.isValid()) hdr.ipv4.protocol = hdr.consensus.protocol;
        else if(hdr.ipv6.isValid()) hdr.ipv6.nextHeader = hdr.consensus.protocol;
        hdr.consensus.setInvalid();
    }

    action consensus_forward(egressSpect_t port){
        standard_metadata.egress_spec = port;
    }

    action consent(){
        if(!hdr.consensus.isValid()){
            // ??. Should have added the consensus first, should always be valid
            return ;
        }
        
        hdr.consensus.allow = hdr.consensus.allow + 1;
    }

    action unconsent(){
        if(!hdr.consensus.isValid()){
            // ??. Should have added the consensus first, should always be valid
            return ;
        }

        hdr.consensus.unallow = hdr.consensus.unallow + 1;
    }

    // Tables definitions
    table ethernet_table {
        key = {
            hdr.ethernet.srcAddr : lpm;
            hdr.ethernet.dstAddr : lpm;
            hdr.ethernet.etherType : exact;
        }

        actions = {
            // add consensus header
            consensus_ingress;

            // consensus header actions
            consent;
            unconsent;
        }

        size = 1024;
        default_action = drop();
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }

        actions = {
            ipv4_forward;
            drop;
            NoAction;

            // consensus header actions
            consent;
            unconsent;
        }

        size = 1024;
        default_action = drop();
    }

    table ipv6_lpm {
        key = {
            hdr.ipv6.dstAddr: lpm;
        }

        actions = {
            ipv6_forward;
            drop;
            NoAction;
            
            // consensus header actions
            consent;
            unconsent;
        }

        size = 1024;
        default_action = drop();
    }

    table consensus_exact {
        key = {
            hdr.consensus.allow : exact;
            hdr.consensus.unallow : exact;
            hdr.consensus.protocol : exact;
        }

        actions = {
            consensus_egress;
            consensus_forward;
            drop;
        }
        
        size = 1024;
        default_action = drop();
    }

    table udp_exact {
        key = {
            hdr.udp.srcPort : exact;
            hdr.udp.dstPort : exact;
            hdr.udp.len : exact;
            hdr.udp.checksum : exact;
        }

        actions = {
            consent;
            unconsent;
        }

        size = 1024;
        default_action = drop();
    }

    table tcp_exact {
        key = {
            hdr.tcp.srcPort : exact;
            hdr.tcp.dstPort : exact;
            hdr.tcp.sequenceNum : exact;
            hdr.checksum : exact;
        }

        actions = {
            consent;
            unconsent;
        }

        size = 1024;
        default_action = drop();
    }

    apply {
        if(hdr.ethernet.isValid()) ethernet_table.apply();

        if(hdr.ipv4.isValid()) ipv4_lpm.apply();
        else if(hdr.ipv6.isValid()) ipv6_lpm.apply();

        if(hdr.consensus.isValid()) consensus_exact.apply();

        if(hdr.tcp.isValid()) tcp_exact.apply();
        else if(hdr.udp.isValid()) udp_exact.apply();
    }
}

/*************************************************************************/
/****************  E G R E S S   P R O C E S S I N G   *******************/
/*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************/
/*************   C H E C K S U M    C O M P U T A T I O N   **************/
/*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
        update_checksum(
            hdr.ipv4.isValid(),
            { hdr.ipv4.version,
              hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

/*************************************************************************/
/***********************  D E P A R S E R  *******************************/
/*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        if(hdr.ipv4.isValid()) packet.emit(hdr.ipv4);
        else if(hdr.ipv6.isValid()) packet.emit(hdr.ipv6);

        if(hdr.consensus.isValid()) packet.emit(hdr.consensus);

        if(hdr.tcp.isValid()) packet.emit(tcp);
        else if(hdr.upd.isValid()) packet.emit(udp);
    }
}

/*************************************************************************/
/**************************  S W I T C H  ********************************/
/*************************************************************************/


V1Switch(
    MyParser(),
    MyVerifyChecksum(),
    MyIngress(),
    MyEgress(),
    MyComputeChecksum(),
    MyDeparser(),
) main;

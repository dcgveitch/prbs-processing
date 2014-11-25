// used for communication via xbee api
import processing.serial.*;
import java.util.concurrent.*;
import com.rapplogic.xbee.api.XBee;
import com.rapplogic.xbee.api.XBeeAddress64;
import com.rapplogic.xbee.api.XBeeException;
import com.rapplogic.xbee.api.XBeeTimeoutException;
import com.rapplogic.xbee.api.ApiId;
import com.rapplogic.xbee.api.AtCommand;
import com.rapplogic.xbee.api.AtCommandResponse;
import com.rapplogic.xbee.api.XBeeResponse;
import com.rapplogic.xbee.api.zigbee.NodeDiscover;

String version = "1.02";
String mySerialPort = "/dev/tty.usbserial-A900UD0N";

// create and initialize a new xbee object
XBee xbee = new XBee();
Queue<XBeeResponse> queue = new ConcurrentLinkedQueue<XBeeResponse>();
XBeeResponse response;
XBeeAddress64 broadcast64 = new XBeeAddress64(0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff);

int error=0, foundIt;

int[] command = new int[10];
int[] commandInt = new int[18];
Date dStart;
Date dSync;
int sizeX=1200, sizeY=500, mButHeight=50, mButWidth=150, mPosX1=10, mPosX2, mPosX3, mPosX4, mPosY=10;
long nodeDiscover=-30000;
int nNodeDL=0;
String downloadStamp;
boolean mButton1, mButton2, allReady;

// make an array list of nodes and buttons
ArrayList switches = new ArrayList();
ArrayList nodes = new ArrayList();
ArrayList savedPackets = new ArrayList();

// create a font for display
PFont font;

// for writing received readings to file
BufferedWriter writer;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

void setup() {
  // Set up display
  size(sizeX, sizeY);
  // Global buttons
  mPosX2= mPosX1 + mButWidth + 10;
  mPosX3= mPosX2 + mButWidth + 10;
  mPosX4= mPosX3 + mButWidth + 10;
  
  smooth();
  font = loadFont("SansSerif-10.vlw");
  textFont(font);  
  PropertyConfigurator.configure(dataPath("")+"log4j.properties");

  // Print a list in case the selected serial port doesn't work out
  println("Beginning...");
  try {
    // opens your serial port defined above, at 9600 baud
    xbee.open(mySerialPort, 57600);
    xbee.addPacketListener(new PacketListener() {
      public void processResponse(XBeeResponse response) {
        queue.offer(response);
      }
    }
    );
  }
  catch (XBeeException e) {
    println("  ** Error opening XBee port: " + e + " **");
    error=1;
  }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
void draw() {
  background(255); // White background
  noStroke();
  fill(0,0,255);
  rect(mPosX1, mPosY, mButWidth, mButHeight);
  rect(mPosX2, mPosY, mButWidth, mButHeight);
  rect(mPosX3, mPosY, mButWidth, mButHeight);
  rect(mPosX4, mPosY, mButWidth, mButHeight);
  stroke(5);
  line(0, mPosY + mButHeight + 10, sizeX, mPosY + mButHeight + 10);
  
  textAlign(CENTER);
  fill(255);
  textSize(16);
  text("Initialise All", mPosX1 + mButWidth/2, mPosY + mButHeight/2 + 4);
  text("Download All", mPosX2 + mButWidth/2, mPosY + mButHeight/2 + 4);
  text("Reset All", mPosX3 + mButWidth/2, mPosY + mButHeight/2 + 4);
  text("Zero All", mPosX4 + mButWidth/2, mPosY + mButHeight/2 + 4);

  if (error == 1) { // Report Serial Problems 
    fill(0);
    text("** Error opening XBee port: **", width*0.4, height*0.5);
  }
  else if (switches.size()==0) {
    fill(0);
    text("Waiting...", width*0.4, height*0.5);
  }

  // Process incoming packets
  while ((response = queue.poll()) != null) {
      try {
        // IF PACKET IS RX_RESPONSE
        if ( response.getApiId() == ApiId.ZNET_RX_RESPONSE) {
          ZNetRxResponse rx = (ZNetRxResponse) response;
          XBeeAddress64 address64 = rx.getRemoteAddress64();
          print("Rx packet received - ");
          
          // Check if Node is registered
          foundIt=0;
          for (int i=0; i < nodes.size(); i++) {      
            if (address64.equals(((NodeDiscover) nodes.get(i)).getNodeAddress64())) {
              foundIt=1;
              println("Recognised address. FLAG: " + rx.getData()[0]);
              
              if (rx.getData()[0] == 0) { // MASTER NODE READY
                println("MASTER NODE READY FLAG");
                masterNRX(i, rx);
                ((Switch) switches.get(i)).nodeReady();
              }
              
              if (rx.getData()[0] == 1) { // NODE READY
                println("NODE READY FLAG");              
                ((Switch) switches.get(i)).nodeReady();
              }
              
              else if (rx.getData()[0] == 2) { // NODE AWAKE
                println("NODE AWAKE FLAG");
                ((Switch) switches.get(i)).nodeAwake();
              }
              else if (rx.getData()[0] == 3) { // MASTER Packet
                println("NODE MASTER");              
                masterRX(i, rx);
              }
              else if (rx.getData()[0] == 4) { // MEASUREMENT Packet
                println("NODE MEASUREMENT");              
                measurementRX(i, rx);
              }
              else if (rx.getData()[0] == 5) { // DATA Packet
                println("NODE DATA " + millis());              
                ((Switch) switches.get(i)).nodeData(rx);
              }
              break;
            }
          }
          
          // If Node is not registered, send 'Node Discover' command and save packet
          if (foundIt==0) {
            println("Unknown address");
            if (millis()-nodeDiscover>1000) {
              println("- Sending node discover...");
              xbee.sendAsynchronous(new AtCommand("ND"));
              nodeDiscover=millis();
            }
            if (rx.getData()[0] == 4) { // MEASUREMENT Packet
              savedPackets.add(rx);
            }
          }
          else {
          // Process packet
          }        
        }  
       
        // IF PACKET IS ND RESPONSE
        else if (response.getApiId() == ApiId.AT_RESPONSE) {
          NodeDiscover node = NodeDiscover.parse((AtCommandResponse) response);
          XBeeAddress64 address64 = node.getNodeAddress64();
          
          // Check if Node is registered
          foundIt=0;
          for (int j=0; j < nodes.size(); j++) {      
            if (address64.equals(((NodeDiscover) nodes.get(j)).getNodeAddress64())) {
              foundIt=1;
              println("Recognised address.");
              break;
            }
          }
          
           // If Node is not registered, add to Node list
          if ((foundIt==0) && !(node.getNodeIdentifier().equals("COMP"))) {
            nodes.add(node);
            switches.add(new Switch(address64, switches.size(), node.getNodeIdentifier()));
            println("Added Node: " + node.getNodeIdentifier());
            println("Total Nodes: " + nodes.size());
            
            for (int i=0; i < savedPackets.size(); i++) {      
              if (address64.equals(((ZNetRxResponse) savedPackets.get(i)).getRemoteAddress64())) {
                println("Adding saved data.");
                measurementRX(switches.size()-1,((ZNetRxResponse) savedPackets.get(i)));
                savedPackets.remove(i);
                break;
              }
            }

          }
        }
      }
      catch (ClassCastException e) {}
      catch (XBeeException ee) {}
  }
  
  allReady=true;
  for (int i =0; i<switches.size(); i++) {
    if(((Switch) switches.get(i)).state != 0) allReady=false;
  }  
  
  // draw the switches on the screen
  for (int i =0; i<switches.size(); i++) {
    ((Switch) switches.get(i)).render();
  }
  
  
  
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
void masterRX(int i, ZNetRxResponse rx) {
  ((Switch) switches.get(i)).type = 1;
  ((Switch) switches.get(i)).seqCount = rx.getData()[1] * 256 + rx.getData()[2];
  ((Switch) switches.get(i)).seqPeriod = rx.getData()[3] * 256 + rx.getData()[4];
  ((Switch) switches.get(i)).seqPos = rx.getData()[5] * 256 + rx.getData()[6];
  ((Switch) switches.get(i)).seqLength = rx.getData()[7] * 256 + rx.getData()[8];
  ((Switch) switches.get(i)).tUpdate = nf(day(),2) + "/" + nf(month(),2) + "/" + str(year()) + " " + nf(hour(),2) + ":" + nf(minute(),2) + ":" + nf(second(),2);
  ((Switch) switches.get(i)).tStatus = ("");
  ((Switch) switches.get(i)).out[0] = rx.getData()[9];
  ((Switch) switches.get(i)).out[1] = rx.getData()[10];
  ((Switch) switches.get(i)).out[2] = rx.getData()[11];
  ((Switch) switches.get(i)).outspd[0] = rx.getData()[12];
  ((Switch) switches.get(i)).outspd[1] = rx.getData()[13];
  ((Switch) switches.get(i)).outspd[2] = rx.getData()[14];
  ((Switch) switches.get(i)).nFans = rx.getData()[15];
  ((Switch) switches.get(i)).fanspd[0] = rx.getData()[16]*10;
  ((Switch) switches.get(i)).fanspd[1] = rx.getData()[17]*10;
  ((Switch) switches.get(i)).fanspd[2] = rx.getData()[18]*10;
  ((Switch) switches.get(i)).fanspd[3] = rx.getData()[19]*10;
  ((Switch) switches.get(i)).fanspd[4] = rx.getData()[20]*10;
  ((Switch) switches.get(i)).fanspd[5] = rx.getData()[21]*10;
  ((Switch) switches.get(i)).fanspd[6] = rx.getData()[22]*10;
  ((Switch) switches.get(i)).fanspd[7] = rx.getData()[23]*10;
  ((Switch) switches.get(i)).fanspd[8] = rx.getData()[24]*10;
  ((Switch) switches.get(i)).fanspd[9] = rx.getData()[25]*10;
  ((Switch) switches.get(i)).fanspd[10] = rx.getData()[26]*10;
  ((Switch) switches.get(i)).fanspd[11] = rx.getData()[27]*10;
  ((Switch) switches.get(i)).volts = (float) (rx.getData()[28] * 256 + rx.getData()[29])/1023*3.3*2;
  ((Switch) switches.get(i)).vcc = (float) (rx.getData()[30] * 256 + rx.getData()[31])/1000; 
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
void masterNRX(int i, ZNetRxResponse rx) {
  ((Switch) switches.get(i)).type = 1;
  ((Switch) switches.get(i)).nFans = rx.getData()[1];
  ((Switch) switches.get(i)).fanspd[0] = rx.getData()[2]*10;
  ((Switch) switches.get(i)).fanspd[1] = rx.getData()[3]*10;
  ((Switch) switches.get(i)).fanspd[2] = rx.getData()[4]*10;
  ((Switch) switches.get(i)).fanspd[3] = rx.getData()[5]*10;
  ((Switch) switches.get(i)).fanspd[4] = rx.getData()[6]*10;
  ((Switch) switches.get(i)).fanspd[5] = rx.getData()[7]*10;
  ((Switch) switches.get(i)).fanspd[6] = rx.getData()[8]*10;
  ((Switch) switches.get(i)).fanspd[7] = rx.getData()[9]*10;
  ((Switch) switches.get(i)).fanspd[8] = rx.getData()[10]*10;
  ((Switch) switches.get(i)).fanspd[9] = rx.getData()[11]*10;
  ((Switch) switches.get(i)).fanspd[10] = rx.getData()[12]*10;
  ((Switch) switches.get(i)).fanspd[11] = rx.getData()[13]*10;
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
void measurementRX(int i, ZNetRxResponse rx) {
  ((Switch) switches.get(i)).type = 2;
  ((Switch) switches.get(i)).seqCount = rx.getData()[1] * 256 + rx.getData()[2];
  ((Switch) switches.get(i)).seqPeriod = rx.getData()[3] * 256 + rx.getData()[4];
  ((Switch) switches.get(i)).seqPos = rx.getData()[5] * 256 + rx.getData()[6];
  ((Switch) switches.get(i)).seqLength = rx.getData()[7] * 256 + rx.getData()[8];
  ((Switch) switches.get(i)).tUpdate = nf(day(),2) + "/" + nf(month(),2) + "/" + str(year()) + " " + nf(hour(),2) + ":" + nf(minute(),2) + ":" + nf(second(),2); 
  ((Switch) switches.get(i)).tStatus = ("");
  ((Switch) switches.get(i)).co2L = rx.getData()[9] * 256 + rx.getData()[10];
  ((Switch) switches.get(i)).ico2L = rx.getData()[11] * 256 + rx.getData()[12];            
  ((Switch) switches.get(i)).co2Max = rx.getData()[13] * 256 + rx.getData()[14];
  ((Switch) switches.get(i)).co2seqMin = rx.getData()[15] * 256 + rx.getData()[16];
  ((Switch) switches.get(i)).co2seqMax = rx.getData()[17] * 256 + rx.getData()[18];
  ((Switch) switches.get(i)).temp = (rx.getData()[19] * 256 + rx.getData()[20])/16.0;
  ((Switch) switches.get(i)).volts = (float) (rx.getData()[21] * 256 + rx.getData()[22])/1023*3.3*2;
  ((Switch) switches.get(i)).vcc = (float) (rx.getData()[23] * 256 + rx.getData()[24])/1000;
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
void nodeInitialise() {  
  if (allReady) {
    text("All ready!", width*0.9, height*0.1);
    try {
      dStart = new Date();
      dStart.setTime(dStart.getTime() + 5000); // Start in 5 secs
      dSync = new Date();   
      println("Initialising!");
      commandInt[0] = (int) 99;       
      commandInt[1] = (int) (dSync.getTime()/1000) >> 24 & 0xff;
      commandInt[2] = (int) (dSync.getTime()/1000) >> 16 & 0xff;
      commandInt[3] = (int) (dSync.getTime()/1000) >> 8 & 0xff;
      commandInt[4] = (int) (dSync.getTime()/1000) & 0xff;
      commandInt[5] = (int) (dStart.getTime()/1000) >> 24 & 0xff;
      commandInt[6] = (int) (dStart.getTime()/1000) >> 16 & 0xff;
      commandInt[7] = (int) (dStart.getTime()/1000) >> 8 & 0xff;
      commandInt[8] = (int) (dStart.getTime()/1000) & 0xff;
      commandInt[9] = (int) 15 >> 8 & 0xff; // Sequence length
      commandInt[10] = (int) 15 & 0xff;
      commandInt[11] = (int) 120 >> 8 & 0xff; // Sequence Period in minutes
      commandInt[12] = (int) 120 & 0xff;
      commandInt[13] = (int) 16; // PRBS Multiple 
      commandInt[14] = (int) 2; // nZones
      commandInt[15] = (int) 40; // z1speed
      commandInt[16] = (int) 40; // z2speed
      commandInt[17] = (int) 0; // z3speed
      
      ZNetTxRequest requestInt = new ZNetTxRequest(broadcast64, commandInt);
      xbee.sendAsynchronous(requestInt);
      println("Sent!");
      mButton1=false;
      for (int i =0; i<switches.size(); i++) {
        ((Switch) switches.get(i)).tStatus="Initialising...";
        }
    }
    catch (XBeeTimeoutException e) {}
    catch (Exception ee) {}
  }
  else println("ALL NODES NOT READY!");
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
void mousePressed() {
  mButtons();
  for (int i=0; i < switches.size(); i++) {
    ((Switch) switches.get(i)).toggleState();
  }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
void mButtons() {
  if(mouseX >=mPosX1 && mouseY >= mPosY && 
       mouseX <=mPosX1+mButWidth && mouseY <= mPosY+mButHeight)
    {
      println("Clicked Master Button 1!");
      mButton1=true;
      nodeInitialise();
    }
    
    if(mouseX >=mPosX2 && mouseY >= mPosY && 
       mouseX <=mPosX2+mButWidth && mouseY <= mPosY+mButHeight) 
    {
      println("Clicked Master Button 2!");
      for (int i =0; i<switches.size(); i++) {
        ((Switch) switches.get(i)).download=true;
      }
    }
    
    if(mouseX >=mPosX3 && mouseY >= mPosY && 
       mouseX <=mPosX3+mButWidth && mouseY <= mPosY+mButHeight) 
    {
      println("Clicked Master Button 3!");
      for (int i =0; i<switches.size(); i++) {
        ((Switch) switches.get(i)).reset=true;
      }
    }
    
    if(mouseX >=mPosX4 && mouseY >= mPosY && 
       mouseX <=mPosX4+mButWidth && mouseY <= mPosY+mButHeight) 
    {
      println("Clicked Master Button 4!");
      for (int i =0; i<switches.size(); i++) {
        ((Switch) switches.get(i)).zero=true;
      }
    }
}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
class Switch {

  int switchNumber, co2L, ico2L, seqCount, seqPeriod, seqPos, seqLength, co2Max, co2seqMin, co2seqMax;
  int dispNumber, butHeight, butWidth, posX, posY1, posY2, posY3, posYT;
  int state, type=0;
  int [] out = new int[3];
  int [] outspd = new int[3];
  int [] outspdD = new int[3];
  int [] fanspd= new int[12];
  int nFans;
  boolean download, reset, zero, spdUpdate;
  float temp, volts, vcc;
  XBeeAddress64 addr64;  // stores the raw address locally
  String tStatus="Starting..", tUpdate="--";
  String downloadStamp="";
  long nodeDownload=-60000;
  
  int [] zeroV = new int[8];
  int [] spanV = new int[8];
  
  String nodeID;

  // initialize switch object:
  Switch(XBeeAddress64 _addr64, int _switchNumber, String _nodeID) { 
    addr64 = _addr64;
    switchNumber = _switchNumber;
    nodeID=_nodeID;
    dispNumber=int(nodeID.substring(1));
    butHeight=50;
    butWidth=mButWidth-50;
    posX = ((dispNumber) * (mButWidth+10)) - (mButWidth-25);
    posY1 = mPosY + mButHeight + 115;
    posY2 = posY1 + butHeight + 10;
    posY3 = posY2 + butHeight + 10;
    posYT = posY3 + butHeight + 10;
    zeroV[1]=31000;
    zeroV[2]=30660;
    zeroV[3]=31131;
    zeroV[4]=30925;
    zeroV[5]=31077;
    zeroV[6]=30934;
    zeroV[7]=31180;
    spanV[1]=8192;
    spanV[2]=7669;
    spanV[3]=7655;
    spanV[4]=8377;
    spanV[5]=8038;
    spanV[6]=8160;
    spanV[7]=8201;    
  }

  String getNodeID() {
    return nodeID;
  }    

  //****************************************************
  void render() { // draw switch on screen
    noStroke(); // remove shape edges
    fill(255,0,0);
    rect(posX, posY1, butWidth, butHeight);
    rect(posX, posY2, butWidth, butHeight);
    rect(posX, posY3, butWidth, butHeight);    
    // show text
    textAlign(CENTER);
    fill(0);
    textSize(16);
    // show actuator address
    text("Node " + nodeID, posX+butWidth/2, posY1 - 75);
    textSize(10);
    text(tStatus, posX+butWidth/2, posY1 - 60);
    text(tUpdate, posX+butWidth/2, posY1 - 50);
    
    
    if (type==1) {
      text("Batt: " + nf(volts,0,2) + "V Vcc: " + nf(vcc,0,2) +"V", posX+butWidth/2, posY1 - 40);
      text("-  Z1Spd  +", posX + butWidth/2, posY1 + butHeight/2 + 4);
      text("-  Z2Spd  +", posX + butWidth/2, posY2 + butHeight/2 + 4);
      text("-  Z3Spd  +", posX + butWidth/2, posY3 + butHeight/2 + 4);
      text(seqCount + "x" + seqPeriod + "min Seqs" + "   " + seqPos + "/" + seqLength + " Steps", posX + butWidth/2, posYT+15);
      text("Out: " + out[0] + " " + out[1] + " " + out[2], posX + butWidth/2, posYT+24);
      text("OutSpd (rpm): " + outspd[0] + " " + outspd[1] + " " + outspd[2] + " ", posX + butWidth/2, posYT+33);
      text("nFans: " + nFans, posX + butWidth/2, posYT+51);
      for (int d_fan=0 ; d_fan < nFans ; d_fan=d_fan+1) {
        text("Fan" + d_fan + ": " + fanspd[d_fan] + "rpm", posX + butWidth/2, posYT+60+d_fan*9);
      }
    }
    else if (type==2) {
      text("Batt: " + nf(volts,0,2) + "V Vcc: " + nf(vcc,0,2) +"V", posX+butWidth/2, posY1 - 40);
      text(co2L + "ppm (" + ico2L + "ppm)", posX + butWidth/2, posY1-20);
      text(nf(temp,0,2) + "dC", posX + butWidth/2, posY1-10);
      text(seqCount + "x" + seqPeriod + "min Seqs" + "   " + seqPos + "/" + seqLength + " Steps", posX + butWidth/2, posYT+15);
      text("Max: " + co2Max + "ppm", posX + butWidth/2, posYT+24);
      text("SeqMin: " + co2seqMin + "ppm", posX + butWidth/2, posYT+33);
      text("SeqMax: " + co2seqMax + "ppm", posX + butWidth/2, posYT+42);
    }
  }
  
  //****************************************************
  void nodeReady() {
   tStatus="NODE READY!";
   state=0;
   reset=false;
   if (download) {
     nNodeDL=0;
     for (int i=0; i<switches.size(); i++) if(((Switch) switches.get(i)).state == 2) nNodeDL=nNodeDL+1;
     println(nNodeDL);
     if (nNodeDL<2){
      try {
          command[0] = (int) 103;
          println("Sending Data Request!");
          ZNetTxRequest request = 
            new ZNetTxRequest(addr64, command);
          xbee.sendAsynchronous(request);
          state=2;
          download=false;
      }
      catch (XBeeTimeoutException e) {println("XBee request timed out");}
      catch (Exception e) {println("unexpected error: " + e + e.getMessage());}
    }
   }
  }
  
  //****************************************************
  void nodeAwake() {
    tStatus="NODE AWAKE!";
    state=1;
    if (reset) {
      try {
          tStatus=("RESETTING...");
          command[0] = (int) 109;
          println("Sending Reset!");
          ZNetTxRequest request = 
            new ZNetTxRequest(addr64, command);
          xbee.sendAsynchronous(request);
          reset=false;
      }
      catch (XBeeTimeoutException e) {println("XBee request timed out");}
      catch (Exception e) {println("unexpected error: " + e + e.getMessage());}
    }
    if (zero) {
      try {
          tStatus=("ZEROING...");
          command[0] = (int) 102;
          command[1] = (int) zeroV[dispNumber] >> 8 & 0xff;
          command[2] = (int) zeroV[dispNumber] & 0xff;
          command[3] = (int) spanV[dispNumber] >> 8 & 0xff;
          command[4] = (int) spanV[dispNumber] & 0xff;
          println("Sending Zero Command");
          ZNetTxRequest request = 
            new ZNetTxRequest(addr64, command);
          xbee.sendAsynchronous(request);
          zero=false;
      }
      catch (XBeeTimeoutException e) {println("XBee request timed out");}
      catch (Exception e) {println("unexpected error: " + e + e.getMessage());}
    }
    if ((type==1) && (spdUpdate)) {
      try {
          tStatus=("Speed Update...");
          command[0] = (int) 110;
          command[1] = (int) outspd[0]+outspdD[0];
          command[2] = (int) outspd[1]+outspdD[1];
          command[3] = (int) outspd[2]+outspdD[2];
          outspdD[0] = 0;
          outspdD[1] = 0;
          outspdD[2] = 0;
          ZNetTxRequest request = 
            new ZNetTxRequest(addr64, command);
          xbee.sendAsynchronous(request);
          println("Sent Speed Update");
          spdUpdate=false;
      }
      catch (XBeeTimeoutException e) {println("XBee request timed out");}
      catch (Exception e) {println("unexpected error: " + e + e.getMessage());}
    }
  }
  //****************************************************
  void nodeData(ZNetRxResponse rx) {
     try {
       tStatus="DOWNLOADING...";
       if (millis()-nodeDownload>60000) {
         downloadStamp="";
         int dataOut[] = rx.getProcessedPacketBytes();
         for (int i=15; i<23; i++) {
           println(char(dataOut[i]));
           downloadStamp=downloadStamp + char(dataOut[i]);
           println(downloadStamp);
         }
         downloadStamp=downloadStamp + "_";
         File f = new File("/Users/davidveitch/Documents/Work/3_PhD/5_Working Calcs/Processing/" + downloadStamp + nodeID + ".csv");
         if (f.exists()) {
           f.delete();
         }         
         nodeDownload=millis();
       }
       else { 
         nodeDownload=millis();
         writer = new BufferedWriter(new FileWriter("/Users/davidveitch/Documents/Work/3_PhD/5_Working Calcs/Processing/" + downloadStamp + nodeID + ".csv", true));
         int dataOut[] = rx.getProcessedPacketBytes();
         for (int i=15; i<(dataOut.length-1); i++) {
           writer.write(dataOut[i]);
         }
         writer.close();
       }
     }
     catch (IOException e) {}
  }
  //****************************************************
  void toggleState() {
    // CHECK BUTTON 1-
    if(mouseX >=posX && mouseY >= posY1 && 
       mouseX <=posX+butWidth/2 && mouseY <= posY1+butHeight) 
    {
      if(type==1) {
        println(nodeID + ": clicked Button 0-!");
        outspdD[0]=outspdD[0]-10;
        spdUpdate=true;
      }
      else {
        download=true;
      }
    }
    
    // CHECK BUTTON 1+
    if(mouseX >=posX+butWidth/2 && mouseY >= posY1 && 
       mouseX <=posX+butWidth && mouseY <= posY1+butHeight) 
    {
      println(nodeID + ": clicked Button 0+!");
      outspdD[0]=outspdD[0]+10;
      spdUpdate=true;
    }
    
    // CHECK BUTTON 2-
    else if(mouseX >=posX && mouseY >= posY2 && 
       mouseX <=posX+butWidth/2 && mouseY <= posY2+butHeight) 
    {
      println(nodeID + ": clicked Button 1-!");
      outspdD[1]=outspdD[1]-10;
      spdUpdate=true;
    }
    
    // CHECK BUTTON 2+
    else if(mouseX >=posX+butWidth/2 && mouseY >= posY2 && 
       mouseX <=posX+butWidth && mouseY <= posY2+butHeight) 
    {
      println(nodeID + ": clicked Button 1+!");
      outspdD[1]=outspdD[1]+10;   
      spdUpdate=true;
    }
    
    // CHECK BUTTON 3-
    else if(mouseX >=posX && mouseY >= posY3 && 
       mouseX <=posX+butWidth/2 && mouseY <= posY3+butHeight) 
    {
      println(nodeID + ": clicked Button 3-!");
      outspdD[2]=outspdD[2]-10;
      spdUpdate=true;
    }
     // CHECK BUTTON 3+
    else if(mouseX >=posX+butWidth/2 && mouseY >= posY3 && 
       mouseX <=posX+butWidth && mouseY <= posY3+butHeight) 
    {
      println(nodeID + ": clicked Button 3+!");
      outspdD[2]=outspdD[2]+10;
      spdUpdate=true;
    }
  }
}


#!/bin/bash
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
echo "<schema elementFormDefault=\"qualified\" xmlns=\"http://www.w3.org/2001/XMLSchema\">"
for i in *.xsd
do 
	targetns=`cat $i|grep -i targetNamespace|cut -d'=' -f 2`; 
	echo -e "\t<import namespace="$targetns" schemaLocation=\""$i"\"/>";
done
echo "</schema>"

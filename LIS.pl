# @Author: Iñigo Ruiz Relloso
# @Date:   2016-02-26T15:28:05+01:00
# @Email:  iruiz077@ikasle.ehu.es
# @Last modified by:   Iñigo Ruiz Relloso
# @Last modified time: 2016-06-08T12:57:46+02:00

use Kamailio;
use Kamailio::Constants;

use POSIX qw(mkfifo);
use Crypt::CBC;

use XML::LibXML;
use XML::LibXML::XPathContext;
use XML::Tidy;

use Try::Tiny;
use DateTime;

#Configuration
$aesKey = "SuperSecureP4ssw0rd";
$locRefLifetime = "3600"; #Seconds

sub publish2loc {

    my $k = shift;
    my $contact= $k->pseudoVar("\$ct");

    my $username= $k->pseudoVar("\$fU");

    my ($sip, $orig, $origport) = split(/[:;]/, $contact);

    my @origip = split(/@/, $orig);

    Kamailio::log(L_NOTICE, "LIS PUBLISH TO LOCATION\n");
    Kamailio::log(L_NOTICE, "Submiting $username user from $origip[-1]:$origport\n");

    open(my $f, '>', "/var/run/kamailio/kamailio_fifo");

    my $readFIFOName = "myLISReadFIFO_$$";

    mkfifo("/tmp/$readFIFOName", 0777);
    open(my $r, '+<', "/tmp/$readFIFOName");

    my $data = << "END";
:ul_add:$readFIFOName
location
$username\@$origip[-1]
sip:$username\@$origip[-1]:$origport
5000
1
0
0
0
0

END

    print $f $data;
    close $f;

    my $answ = <$r>;

    Kamailio::log(L_NOTICE, "Kamailio answered: ".$answ."\n");

    close $r;
    unlink "/tmp/$readFIFOName";
    return 0;

}

sub setInterface {
    $interface = shift;
    return 0;
}

sub setURI {
    $uri = shift;
    return 0;
}

sub setBody {
    $b = shift;
    return 0;
}

sub setIP {
    $id = shift;
    $idType = "ip";
    return 0;
}

sub setUsername {
    $username = shift;
    return 0;
}

sub locReq {
    Kamailio::log(L_NOTICE, "LIS Perl Module\n");
    Kamailio::log(L_NOTICE, "Body: ".$b."\n");

    $exact = 0;
    $byRef = 0;

    if (length($b) == 0)
    {
        Kamailio::AVP::add("answ", genError("requestError","Body of the HELD Request empty"));
        return 0;
    }

    try {
        my $doc = XML::LibXML->new()->parse_string($b);
        my $xpc = XML::LibXML::XPathContext->new($doc);
        $xpc->registerNs(d => 'urn:ietf:params:xml:ns:geopriv:held');
        $xpc->registerNs(id => 'urn:ietf:params:xml:ns:geopriv:held:id');
        $xpc->registerNs(f => 'urn:ietf:params:xml:ns:geopriv:held:flow');

        if ($xpc->findnodes('/d:locationRequest')->size() > 0)
        {
            if ($xpc->findnodes('/d:locationRequest/d:locationType')->size() > 0)
            {
                my $locReqTypeNode = $xpc->findnodes('/d:locationRequest/d:locationType')->get_node(0);
                if ($locReqTypeNode->hasAttributes())
                {
                    foreach my $a ($locReqTypeNode->attributes())
                    {
                        if ($a->nodeName() eq 'exact' && $a->nodeValue() eq 'true')
                        {
                            $exact = 1;
                            Kamailio::log(L_NOTICE, "Exact: TRUE\n");
                        }
                    }
                }

                @locationReqTypes = split(' ', $locReqTypeNode->textContent());
                Kamailio::log(L_NOTICE, "locationTypes: ". join(', ', @locationReqTypes));
            } else {
                @locationReqTypes = ('any');
            }

            my ($ref) = $uri =~ m/\/LIS\/locByRef\/(.*)/g;
            if (defined $ref)
            {
                locDeRef($uri, \@locationReqTypes);
                return 0;
            }

            if ($xpc->findnodes('/d:locationRequest/id:device')->size() > 0)
            {
                if ($xpc->findnodes('/d:locationRequest/id:device/id:ip')->size() > 0)
                {
                    $id = $xpc->findnodes('/d:locationRequest/id:device/id:ip')->get_node(0)->textContent();
                    Kamailio::log(L_NOTICE, "3rd Party Request for $id\n");
                }
                elsif ($xpc->findnodes('/d:locationRequest/id:device/id:uri')->size() > 0)
                {
                    $id = $xpc->findnodes('/d:locationRequest/id:device/id:uri')->get_node(0)->textContent();
                    $idType = "sipuri";
                    Kamailio::log(L_NOTICE, "3rd Party Request for $id\n");
                }
            }
            if ($xpc->findnodes('/d:locationRequest/f:flow')->size() > 0)
            {
                Kamailio::log(L_NOTICE, "3rd Party Request using flow ID\n");
                my $flowNode = $xpc->findnodes('/d:locationRequest/f:flow')->get_node(0);
                if ($flowNode->hasAttributes())
                {
                    foreach my $a ($flowNode->attributes())
                    {
                        if (
                        ($a->nodeName() eq 'layer3' && $a->nodeValue() ne 'ipv4') ||
                        ($a->nodeName() eq 'layer4' && !($a->nodeValue() eq 'tcp' || $a->nodeValue() eq 'udp'))
                        )
                        {
                            Kamailio::AVP::add("answ", genError("unsupportedMessage",
                            "Unsupported flow layer3/layer4 indicators. We only support IPv4 with UDP or TCP."));
                            return 1;
                        }
                    }
                }

                if ($xpc->findnodes('/d:locationRequest/f:flow/f:src')->size() > 0)
                {
                    if ($xpc->findnodes('/d:locationRequest/f:flow/f:src/f:address')->size() > 0)
                    {
                        $id = $xpc->findnodes('/d:locationRequest/f:flow/f:src/f:address')->get_node(0)->textContent();
                    }else
                    {
                        Kamailio::AVP::add("answ", genError("requestError",
                        "Missing <address> element in <src> element in Flow ID"));
                        return 1;
                    }

                    if ($xpc->findnodes('/d:locationRequest/f:flow/f:src/f:port')->size() > 0)
                    {
                        $id .= ":".$xpc->findnodes('/d:locationRequest/f:flow/f:src/f:port')->get_node(0)->textContent();
                    }else
                    {
                        Kamailio::AVP::add("answ", genError("requestError",
                        "Missing <port> element in <src> element in Flow ID"));
                        return 1;
                    }
                }else
                {
                    Kamailio::AVP::add("answ", genError("requestError",
                    "Missing <src> element in Flow ID"));
                    return 1;
                }
            }

            Kamailio::AVP::add("answ","query");
            Kamailio::AVP::add("query",genPresSQL($id, $idType));
            return 0;
        } else
        {
            Kamailio::AVP::add("answ", genError("xmlError","Missing locationRequest element"));
            return 1;
        }
    }catch {
        Kamailio::AVP::add("answ", genError("xmlError","Error parsing XML Body\n".$_));
        return 1;
    }
}

sub locReq2 {
    $sqlres = shift;

    if (length($sqlres) == 0)
    {
        Kamailio::AVP::add("answ",genError("notLocatable","Location query for device with ID ($idType) $id returned empty result."));
    }else
    {
        try {
            my $doc = XML::LibXML->new()->parse_string($sqlres);
            my $xpc = XML::LibXML::XPathContext->new($doc);
            $xpc->registerNs(dm => 'urn:ietf:params:xml:ns:pidf:data-model');
            $xpc->registerNs(gp => 'urn:ietf:params:xml:ns:pidf:geopriv10');
            $xpc->registerNs(gml => 'http://www.opengis.net/gml');
            $xpc->registerNs(ca => 'urn:ietf:params:xml:ns:pidf:geopriv10:civicAddr');
            $xpc->registerNs(p => 'urn:ietf:params:xml:ns:pidf');

            my @returnLocs = ();
            my @returnURIS = ();
            my $geoDone = 0;
            my $urlDone = 0;

            my $presEntity = "";

            my $presenceNode = $xpc->findnodes('/p:presence')->get_node(0);
            if ($presenceNode->hasAttributes())
            {
                foreach my $a ($presenceNode->attributes())
                {
                    if ($a->nodeName() eq 'entity')
                    {
                        $presEntity = $a->nodeValue();
                        Kamailio::log(L_NOTICE, "Presence Entity: $presEntity\n");
                    }
                }
            }
            if ($presEntity eq "")
            {
                die("Entity attribute not present in presence document");
            }

            TYPES:
            foreach my $locationReqType (@locationReqTypes) {
                Kamailio::log(L_NOTICE, "Gathering info for LocType: ".$locationReqType."\n");

                if ($locationReqType eq "civic" || $locationReqType eq "any") {
                    Kamailio::log(L_NOTICE, "Gathering info for CIVIC Type\n");

                    foreach my $locNode ($xpc->findnodes('//gp:geopriv/gp:location-info')) {
                    	if ($xpc->findnodes('./ca:civicAddress', $locNode)->size() > 0)
                    	{
                            Kamailio::log(L_NOTICE, "Found a CIVIC Info\n");
                    		push(@returnLocs, $locNode);
                            if ($exact)
                            {
                                next TYPES;
                                return 0;
                            }
                    	}
                    }
                    if ($exact)
                    {
                        Kamailio::AVP::add("answ", genError("cannotProvideLiType", "Device reported Location Object does not contain Civic information, and exact is set to TRUE."));
                        return 0;
                    }
                }
                if ((!$geoDone) && (!$exact || $locationReqType eq "geodetic" || $locationReqType eq "any")) {
                    Kamailio::log(L_NOTICE, "Gathering info for GEO Type\n");
                    $geoDone = 1;

                    foreach my $locNode ($xpc->findnodes('//gp:geopriv/gp:location-info')) {
                        if ($xpc->findnodes('./ca:civicAddress', $locNode)->size() == 0)
                        {
                            Kamailio::log(L_NOTICE, "Found a GEO Info\n");
                            #TODO: Algún modo de traducir NS's o utilizar otro documento
                            push(@returnLocs, $locNode);
                            if ($exact)
                            {
                                next TYPES;
                                return 0;
                            }
                        }
                    }
                    if ($exact)
                    {
                        Kamailio::AVP::add("answ", genError("cannotProvideLiType", "Device reported Location Object does not contain Geodetic information, and exact is set to TRUE."));
                        return 0;
                    }
                }
                if ((!$urlDone && !$byRef) && (!$exact || $locationReqType eq "locationURI" || $locationReqType eq "any")) {

                    Kamailio::log(L_NOTICE, "Gathering info for URL Type\n");
                    Kamailio::log(L_NOTICE, "User for URL gen: $presEntity\n");

                    my $cipher = Crypt::CBC->new(
                    			   -key    => $aesKey,
                    			   -cipher => "Crypt::OpenSSL::AES"
                    	   );
                    my $urlHash = $cipher->encrypt_hex($presEntity."|".time());

                    my $url = "http://$interface/LIS/locByRef/".$urlHash;

                    $urlDone = 1;
                    push(@returnURIS, $url);
                }
            }

            Kamailio::AVP::add("answ", genLocResp(\@returnURIS, \@returnLocs, $presEntity));
        } catch {
            Kamailio::AVP::add("answ", genError("locationUnknown","Error parsing stored presence info"));
        }
    }
}

sub locDeRef {
    my $uri = shift;
    @locationReqTypes = @{$_[0]};

    Kamailio::log(L_NOTICE, "LIS Perl Module\n");
    Kamailio::log(L_NOTICE, "GET URI: $uri");

    my ($ref, $pepe) = $uri =~ m/\/LIS\/locByRef\/(.*)/g;

    if (defined $ref)
    {
        Kamailio::log(L_NOTICE, "locRef found: $ref");

        my $cipher = Crypt::CBC->new(
                       -key    => $aesKey,
                       -cipher => "Crypt::OpenSSL::AES"
               );

        try {
            my $decref = $cipher->decrypt_hex($ref);
            my ($contact, $timestamp) = split(/\|/, $decref);

            Kamailio::log(L_NOTICE, "DECREF: $decref ==> Contact: $contact, Time: $timestamp");

            if (time()-$timestamp > $locRefLifetime)
            {
                Kamailio::AVP::add("answ", genError("requestError","Expired location reference token"));
            }else
            {
                if (!@locationReqTypes)
                {
                    @locationReqTypes = ('geodetic','civic');
                }

                Kamailio::log(L_NOTICE, "DEREF locationTypes: ". join(', ', @locationReqTypes));

                $byRef = 1;
                Kamailio::AVP::add("answ","query");
                Kamailio::AVP::add("query",genPresSQL($contact, "sipuri"));
            }
        } catch {
            Kamailio::AVP::add("answ", genError("requestError","Corrupted reference token"));
            return 0;
        }

    }else
    {
        Kamailio::AVP::add("answ", genGreet());
    }
}

sub genGreet {
    my $greet = << "END";
<?xml version="1.0"?>
<error xmlns="urn:ietf:params:xml:ns:geopriv:held" code="requestError">
    <message xml:lang="en">
        This is the Nemergent LIS Server, please issue HELD POST Requests Only.
    </message>
</error>
END
}

sub genError {
    my $error = << "END";
<?xml version="1.0"?>
<error xmlns="urn:ietf:params:xml:ns:geopriv:held" code="@_[0]">
    <message xml:lang="en">
        @_[1]
    </message>
</error>

END
}

sub genPresSQL {

# TODO: This is a potentially improvable section, as building SQL statements by
# concatenation can lead to serious security issues.

    my $SQL = "";
    my $s_contact = @_[0];
    $s_contact =~ s/([\\"'\0\n\r\cZ])//g;
    if (@_[1] eq "ip")
    {
        $SQL = "SELECT body, CONCAT(username, '\@', domain) FROM `presentity` WHERE CONCAT(username, '\@', domain) =
        ( SELECT CONCAT(username, '\@', domain) FROM `location` WHERE contact LIKE '%$s_contact%' LIMIT 1 )
        AND event='presence' ORDER BY received_time DESC LIMIT 1 ";
    }

    if (@_[1] eq "sipuri")
    {
        $SQL = "SELECT body, CONCAT(username, '\@', domain) FROM `presentity` WHERE ExtractValue(body, '/presence/\@entity') =
        '$s_contact' AND event='presence' ORDER BY received_time DESC LIMIT 1";
    }


    Kamailio::log(L_NOTICE, "LIS Query for presence records:\n". $SQL ."\n");
    return $SQL;
}

sub genLocResp {
    my @locURIS = @{$_[0]};
    my @locINFOS = @{$_[1]};

    if (scalar @locURIS == 0 && scalar @locINFOS == 0)
    {
        return genError("cannotProvideLiType","An unknown LI type was specified");
    }

    print( "Generating LocResp with ".scalar @locURIS." URL's and ".scalar @locINFOS." LOC info's\n");

    my $now = DateTime->now()->iso8601().'Z';
    my $expiry = DateTime->now()->add( seconds => $locRefLifetime )->iso8601().'Z';

    my $doc1 = XML::LibXML::Document->new('1.0', 'utf-8');
    my $root = $doc1->createElementNS("urn:ietf:params:xml:ns:geopriv:held","locationResponse");


    #Location URI's
    if (scalar @locURIS > 0)
    {
        my $e_uriset = $doc1->createElement("locationUriSet");
        $e_uriset->setAttribute("expires",$expiry);

        foreach my $uri (@locURIS) {
            my $e_uri = $doc1->createElement("locationURI");
            $e_uri->appendText($uri);
            $e_uriset->addChild($e_uri);
        }
        $root->addChild($e_uriset);
    }

    #Location Info
    if (scalar @locINFOS > 0)
    {
        my $e_presence = $doc1->createElementNS("urn:ietf:params:xml:ns:pidf", "presence");
        $e_presence->setAttribute("entity",@_[2]);

        my $e_tuple = $doc1->createElement("tuple");
        $e_tuple->setAttribute("id", "b650sf789nd");

        my $e_status = $doc1->createElement("status");

        foreach my $locinfo (@locINFOS) {
            my $e_geopriv = $doc1->createElementNS("urn:ietf:params:xml:ns:pidf:geopriv10", "geopriv");
            $e_geopriv->addChild($doc1->importNode($locinfo));

            my $e_usagerules = $doc1->createElement("usage-rules");
            $e_usagerules->setNamespace("urn:ietf:params:xml:ns:pidf:geopriv10:basicPolicy", "gbp",0);
            my $e_retention = $doc1->createElement("retention-expiry");
            $e_retention->appendText($expiry);
            $e_usagerules->addChild($e_retention);

            $e_geopriv->addChild($e_usagerules);

            $e_status->addChild($e_geopriv);
        }

        my $e_timestamp = $doc1->createElement("timestamp");
        $e_timestamp->appendText($now);

        $e_tuple->addChild($e_status);
        $e_tuple->addChild($e_timestamp);
        $e_presence->addChild($e_tuple);

        $root->addChild($e_presence);
    }

    $doc1->setDocumentElement($root);

    my $tidy_obj = XML::Tidy->new('xml' => $doc1->toString());
    $tidy_obj->tidy();

    return $tidy_obj->toString();
}

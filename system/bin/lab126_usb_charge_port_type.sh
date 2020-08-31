# Copyright (C) 2016 Amazon Technologies, Inc. All Rights Reserved
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Description:
# Export the USB charge port type read from sysfs to an Android property
#

TAG="lab126_usb_charge_port_type: "

mlog() {
    echo $TAG $@ > /dev/kmsg
}

setprop sys.usb.charge_type unknown

hardware=`getprop ro.hardware`

if [ "$hardware" != "mt8127" ] ; then
    mlog "Unknowm hardware type"
    exit;

fi

if [ ! -f /sys/lab126/usb_charge_type ] ; then
    mlog "Cannot get charge type"
    exit;
fi

charge_type=`cat /sys/lab126/usb_charge_type`
if [ -n "$charge_type" ] ; then

    # validate the value so apps reading the value aren't left to the whims of
    # driver developers...
    case "$charge_type" in
    1)
    charge_type=standard_host
        ;;
    2)
    charge_type=charging_host
        ;;
    3)
    charge_type=wall_charger
        ;;
    *)
        mlog "Unknown charge type: $charge_type"
        exit
        ;;
    esac
    mlog "Setting charge type to " $charge_type
    setprop sys.usb.charge_type $charge_type
fi


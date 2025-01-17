{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module API.UI.Cancel
  ( API,
    handler,
    CancelAPI,
    GetCancellationDuesDetailsAPI,
    getCancellationDuesDetails,
  )
where

import qualified Beckn.ACL.Cancel as ACL
import qualified Domain.Action.UI.Cancel as DCancel
import qualified Domain.Types.Booking as SRB
import qualified Domain.Types.Merchant as Merchant
import qualified Domain.Types.Person as Person
import Environment
import Kernel.Prelude
import Kernel.Types.APISuccess (APISuccess (Success))
import Kernel.Types.Id
import Kernel.Utils.Common
import Servant
import qualified SharedLogic.CallBPP as CallBPP
import Storage.Beam.SystemConfigs ()
import Tools.Auth

type API =
  SoftCancelAPI
    :<|> GetCancellationDuesDetailsAPI
    :<|> CancelAPI

type GetCancellationDuesDetailsAPI =
  "rideBooking"
    :> Capture "rideBookingId" (Id SRB.Booking)
    :> "cancellationDues"
    :> TokenAuth
    :> Get '[JSON] DCancel.CancellationDuesDetailsRes

type SoftCancelAPI =
  "rideBooking"
    :> Capture "rideBookingId" (Id SRB.Booking)
    :> "softCancel"
    :> TokenAuth
    :> Post '[JSON] APISuccess

type CancelAPI =
  "rideBooking"
    :> Capture "rideBookingId" (Id SRB.Booking)
    :> "cancel"
    :> TokenAuth
    :> ReqBody '[JSON] DCancel.CancelReq
    :> Post '[JSON] APISuccess

-------- Cancel Flow----------

handler :: FlowServer API
handler =
  softCancel
    :<|> getCancellationDuesDetails
    :<|> cancel

softCancel ::
  Id SRB.Booking ->
  (Id Person.Person, Id Merchant.Merchant) ->
  FlowHandler APISuccess
softCancel bookingId (personId, merchantId) =
  withFlowHandlerAPI . withPersonIdLogTag personId $ do
    dCancelRes <- DCancel.softCancel bookingId (personId, merchantId)
    cancelBecknReq <- ACL.buildCancelReqV2 dCancelRes Nothing
    void $ withShortRetry $ CallBPP.cancelV2 merchantId dCancelRes.bppUrl cancelBecknReq
    return Success

getCancellationDuesDetails ::
  Id SRB.Booking ->
  (Id Person.Person, Id Merchant.Merchant) ->
  FlowHandler DCancel.CancellationDuesDetailsRes
getCancellationDuesDetails _bookingId (personId, merchantId) =
  withFlowHandlerAPI . withPersonIdLogTag personId $ do
    DCancel.getCancellationDuesDetails (personId, merchantId)

cancel ::
  Id SRB.Booking ->
  (Id Person.Person, Id Merchant.Merchant) ->
  DCancel.CancelReq ->
  FlowHandler APISuccess
cancel bookingId (personId, merchantId) req =
  withFlowHandlerAPI . withPersonIdLogTag personId $ do
    dCancelRes <- DCancel.cancel bookingId (personId, merchantId) req
    void $ withShortRetry $ CallBPP.cancelV2 merchantId dCancelRes.bppUrl =<< ACL.buildCancelReqV2 dCancelRes req.reallocate
    return Success

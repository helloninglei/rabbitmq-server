%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ Management Plugin.
%%
%%   The Initial Developer of the Original Code is GoPivotal, Inc.
%%   Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_mgmt_wm_channels).

-export([init/3, rest_init/2, to_json/2, content_types_provided/2, is_authorized/2,
         augmented/2]).
-export([variances/2]).
-export([clean_consumer_details/1]).

-import(rabbit_misc, [pget/2, pset/3]).

-include("rabbit_mgmt.hrl").
-include_lib("rabbit_common/include/rabbit.hrl").

%%--------------------------------------------------------------------

init(_, _, _) -> {upgrade, protocol, cowboy_rest}.

rest_init(Req, _Config) ->
    {ok, rabbit_mgmt_cors:set_headers(Req, ?MODULE), #context{}}.

variances(Req, Context) ->
    {[<<"accept-encoding">>, <<"origin">>], Req, Context}.

content_types_provided(ReqData, Context) ->
   {[{<<"application/json">>, to_json}], ReqData, Context}.

to_json(ReqData, Context) ->
    try
        rabbit_mgmt_util:reply_list_or_paginate(augmented(ReqData, Context),
            ReqData, Context)
    catch
        {error, invalid_range_parameters, Reason} ->
            rabbit_mgmt_util:bad_request(iolist_to_binary(Reason), ReqData, Context)
    end.

is_authorized(ReqData, Context) ->
    rabbit_mgmt_util:is_authorized(ReqData, Context).

augmented(ReqData, Context) ->
    MemberPids = pg2:get_members(management_db),
    {PidResults, _} = delegate:call(MemberPids, "delegate_management_",
                                    {get_all_channels, rabbit_mgmt_util:range(ReqData)}),
    Channels = lists:append([R || {_, R} <- PidResults]),

    Channels0 = [clean_consumer_details(C) || C <- Channels ],

    rabbit_mgmt_util:filter_conn_ch_list(Channels0, ReqData, Context).

clean_consumer_details(Channel) ->
     case pget(consumer_details, Channel) of
         undefined -> Channel;
         Cds ->
             Cons = [clean_channel_details(
                       lists:keydelete(channel_pid, 1, Con))
                     || Con <- Cds],
             pset(consumer_details, Cons, Channel)
     end.

clean_channel_details(Consumer) ->
     case pget(channel_details, Consumer) of
         undefined -> Consumer;
         Chd ->
             pset(channel_details,
                  lists:keydelete(pid, 1, Chd),
                  Consumer)
     end.

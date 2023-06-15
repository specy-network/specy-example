import { BigInt, cosmos, log, store, crypto, ByteArray } from "@graphprotocol/graph-ts";
import { merkellist, rewardlist } from "../generated/schema";


export function handleSetRewardList(data: cosmos.EventData): void {

  let list = new rewardlist("reward_list")
  list.list = data.event.getAttributeValue("reward_list").split(",");
  log.info("handle reward list successed ,list:{}", [data.event.getAttributeValue("reward_list")])
  list.save()
}


export function handleSetMerkelList(data: cosmos.EventData): void {

  let list = new merkellist(data.block.header.height.toString())
  list.root = data.event.getAttributeValue("merkel_root");
  log.info("handle merker list successed ,list:{}", [data.event.getAttributeValue("merkel_root")])
  list.save()
}
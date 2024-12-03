///
/// # Anonymized Replica
///
/// This module implement a logical decoder to create an 
/// anonymized replica of a database
///
/// https://github.com/dalibo/hackingpg/blob/main/journee5/audit/plugin_audit.c

pub fn output_plugin_init(pg_sys::OutputPluginCallbacks *cb)
{
	cb.begin_cb  = Some(pg_decode_begin_txn);
	cb.change_cb = Some(pg_decode_change);
	cb.commit_cb = Some(pg_decode_commit_txn);
}


/// BEGIN callback 
fn pg_decode_begin_txn(
    pg_sys::LogicalDecodingContext *ctx, 
    pg_sys::ReorderBufferTXN *txn)
{
}

/// COMMIT callback
fn pg_decode_commit_txn(
    pg_sys::LogicalDecodingContext *ctx, 
    pg_sys::ReorderBufferTXN *txn,
	pg_sys::XLogRecPtr commit_lsn)
{
}


/// callback for individual changed tuples
///
fn pg_decode_change(
    pg_sys::LogicalDecodingContext *ctx, 
    pg_sys::ReorderBufferTXN *txn,
	pg_sys::Relation relation, 
    pg_sys::ReorderBufferChange *change
)
{
/*
	AuditDecodingData *data;
	MemoryContext old;
	Form_pg_class class_form;

	data = ctx->output_plugin_private;

	old = MemoryContextSwitchTo(data->context);

	OutputPluginPrepareWrite(ctx, true);

	class_form = RelationGetForm(relation);
	appendStringInfoString(ctx->out,
		quote_qualified_identifier(get_namespace_name(get_rel_namespace(RelationGetRelid(relation))),
		class_form->relrewrite ?
			get_rel_name(class_form->relrewrite) :
			NameStr(class_form->relname)));

	switch (change->action)
	{
		case REORDER_BUFFER_CHANGE_INSERT:
			appendStringInfoString(ctx->out, " INSERT");
			break;
		case REORDER_BUFFER_CHANGE_UPDATE:
			appendStringInfoString(ctx->out, " UPDATE");
			break;
		case REORDER_BUFFER_CHANGE_DELETE:
			appendStringInfoString(ctx->out, " DELETE");
			break;
		default:
			Assert(false);
	}

	MemoryContextSwitchTo(old);
	MemoryContextReset(data->context);

	OutputPluginWrite(ctx, true);
*/
}
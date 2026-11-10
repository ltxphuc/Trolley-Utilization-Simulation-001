USE [CCTJobSeqDB]
GO
/****** Object:  StoredProcedure [dbo].[P_Task_Calculate]    Script Date: 21/04/2026 1:43:24 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
-- =============================================
-- Author:		<Damon gu>
-- Create date: <2024-12-02>
-- Description:	 重写CCT JOB SEQ 每日任务计算
-- =============================================
ModifyBy:
	Damon gu 2025/02/14 小缸指定床需求
	Damon gu 2025/02/28 后拉只紧跟相同PPC计划时间非后拉
	Damon gu 2025/04/10 合缸床次排在非合缸床后后面逻辑修改
	Damon gu 2025/05/07 找物料取消只循环20次限制
	Damon gu 2025/08/21 锁定床次内按上一次顺序排序
	Damon gu 2025/09/22 特殊床次排在特殊工位
	Damon gu 2025/10/20 同制单同缸合并逻辑参数控制
	Damon gu 2025/12/22 增加没有找到可排床次LOG
EXEC [dbo].[P_Task_Calculate] @IsDebug=1
DELETE FROM SPD_Order_Scheduling
delete from [dbo].[SPD_Order_Cut_Plan_Date_ALL_Lot]
SELECT * FROM [dbo].[SPD_Order_Cut_Plan_Date_ALL_Lot] WHERE RID='02EA08E6-01B5-4B8B-BDE9-4B870A10DD65'
*/

Declare 

	@Calculate_Type VARCHAR(5) = 'A' --A:系统计算 B:预算
	,@LineBalance_WorkHours DECIMAL(18, 2) = 10 --每日上班小时数  
	,@Calculate_LotNumber VARCHAR(50) = '' --预算批次 
	,@Calculate_LotNumber_Case VARCHAR(50) = '' --每一个Case的RID
	,@IS_Use_Last_Case VARCHAR(5) = 'N'
	,@IS_Special_Calculate VARCHAR(5) = 'N'
	,@Action_Type VARCHAR(50) = ''
	,@Action_ID VARCHAR(50) = ''
	,@IsDebug INT = 0


BEGIN
	SET NOCOUNT OFF;

	IF OBJECT_ID('tempdb..#SPD_Order_Scheduling_log') IS NOT NULL
		DROP TABLE #SPD_Order_Scheduling_log

	SELECT *
	INTO #SPD_Order_Scheduling_log
	FROM SPD_Order_Scheduling_log WITH (NOLOCK)
	WHERE 1 = 2

	BEGIN TRY
		INSERT INTO LOGS (
			RID
			,UserID
			,ActionTime
			,FullURL
			,Source
			,StackTrace
			,Message
			,LogType
			)
		SELECT RID = convert(VARCHAR(50), newid())
			,UserID = @Action_ID
			,ActionTime = getdate()
			,FullURL = @Action_Type
			,Source = 'SP_Task_Calculate'
			,StackTrace = ''
			,Message = ''
			,LogType = ''
	END TRY

	BEGIN CATCH
	END CATCH

	--SELECT * FROM TB_Calculate_Task ORDER BY Action_Date DESC
	IF NOT EXISTS (
			SELECT TOP 1 1
			FROM System_Table WITH (NOLOCK)
			WHERE SYS_CODE = 'P_Task_Calculate'
			)
	BEGIN
		INSERT INTO System_Table (
			SYS_CODE
			,SYS_DESCRIPTION
			,SYS_VALUE
			,SYS_USER
			,SYS_DATE
			,sys_value2
			,Sys_Type
			,Sys_Value1
			,Sys_Value3
			,CreatedBy
			,CreatedDate
			,LastModifiedBy
			,LastModifiedDate
			,Sys_Value4
			,Sys_Sdescription
			)
		SELECT SYS_CODE = 'P_Task_Calculate'
			,SYS_DESCRIPTION = N'控制JOB不能重复执行'
			,SYS_VALUE = '1'
			,SYS_USER = ''
			,SYS_DATE = getdate()
			,sys_value2 = ''
			,Sys_Type = ''
			,Sys_Value1 = ''
			,Sys_Value3 = ''
			,CreatedBy = 'lwzxgu'
			,CreatedDate = getdate()
			,LastModifiedBy = 'lwzxgu'
			,LastModifiedDate = getdate()
			,Sys_Value4 = ''
			,Sys_Sdescription = 'P_Task_Calculate'
	END
	ELSE
	BEGIN
		UPDATE System_Table
		SET SYS_DATE = getdate()
			,SYS_VALUE = '1'
		WHERE SYS_CODE = 'P_Task_Calculate'
			AND (
				SYS_VALUE = '0'
				OR SYS_DATE <= DATEADD(MINUTE, - 10, GETDATE())
				)
	END

	IF @@rowcount <= 0
	BEGIN
		RETURN;
	END

	DECLARE @Version_ServerName NVARCHAR(50) = ''
		,@BeginTime DATETIME = getdate()
		,@Step VARCHAR(MAX) = ''

	BEGIN TRY
		SELECT @Version_ServerName = isnull(Sys_Value2, '') + '_' + isnull(Sys_Value1, '')
		FROM System_table
		WHERE Sys_Code = 'Version_ServerName'

		DECLARE @JsonStr NVARCHAR(MAX) = NULL
			,@Action_Message NVARCHAR(MAX) = ''
			,@MO_No VARCHAR(50) = ''
			,@Ori_RID VARCHAR(50) = ''
			,@Ori_Plan_Date DATETIME = NULL

		EXEC [dbo].[P_Task_Calculate_Pre] --准备需要排的单

		EXEC [dbo].[P_Task_CreateBreakTime] --创建班次时间&空闲时间区间

		DECLARE @Work_Date DATE = NULL

		SELECT TOP 1 @Work_Date = Plan_date
		FROM TB_Calculate_Shift WITH (NOLOCK)

		IF isnull(@Calculate_LotNumber, '') = ''
		BEGIN
			SELECT TOP 1 @Calculate_LotNumber = Lot_number_Cur
			FROM [dbo].[V_TB_Order_Cut_Plan_Date_ALL_Lot]
			ORDER BY Create_Date DESC
		END

		IF object_id('tempdb..#TB_SpreadMachine') IS NOT NULL
			DROP TABLE #TB_SpreadMachine

		SELECT *
			,Marker_Width = CONVERT(DECIMAL(18, 4), NULL)
			,IsStripe = CONVERT(BIT, 0) --是否可排横间
			,IsPadPrint = CONVERT(BIT, 0) --是否排PadPrint
			,IsAbnormal = CONVERT(BIT, 0) --是否排异常排除单
			,IsFirstTable = CONVERT(BIT, 0) --是否排首床
		INTO #TB_SpreadMachine
		FROM TB_SpreadMachine WITH (NOLOCK)

		UPDATE T
		SET T.IsStripe = 1
		--,T.IsPadPrint = CASE 
		--	WHEN V.Code = 'PadPrinting'
		--		THEN 1
		--	ELSE ISNULL(T.IsPadPrint, 0)
		--	END
		--,T.IsAbnormal = CASE 
		--	WHEN V.Code = 'ExcludeSO'
		--		THEN 1
		--	ELSE ISNULL(T.IsAbnormal, 0)
		--	END
		--,T.IsFirstTable = CASE 
		--	WHEN V.Code = 'First_Bed'
		--		THEN 1
		--	ELSE ISNULL(T.IsFirstTable, 0)
		--	END
		FROM TB_SpreadMachine_VisualSetting V WITH (NOLOCK)
		INNER JOIN #TB_SpreadMachine T ON V.SpreadMachine_Rid = T.RID
		WHERE V.Code = 'Strip'

		UPDATE T
		SET T.IsPadPrint = 1
		--,T.IsAbnormal = CASE 
		--	WHEN V.Code = 'ExcludeSO'
		--		THEN 1
		--	ELSE ISNULL(T.IsAbnormal, 0)
		--	END
		--,T.IsFirstTable = CASE 
		--	WHEN V.Code = 'First_Bed'
		--		THEN 1
		--	ELSE ISNULL(T.IsFirstTable, 0)
		--	END
		FROM TB_SpreadMachine_VisualSetting V WITH (NOLOCK)
		INNER JOIN #TB_SpreadMachine T ON V.SpreadMachine_Rid = T.RID
		WHERE V.Code = 'PadPrint'

		UPDATE T
		SET T.IsAbnormal = 1
		--,T.IsFirstTable = CASE 
		--	WHEN V.Code = 'First_Bed'
		--		THEN 1
		--	ELSE ISNULL(T.IsFirstTable, 0)
		--	END
		FROM TB_SpreadMachine_VisualSetting V WITH (NOLOCK)
		INNER JOIN #TB_SpreadMachine T ON V.SpreadMachine_Rid = T.RID
		WHERE V.Code = 'ExcludeSO'

		UPDATE T
		SET T.IsFirstTable = 1
		FROM TB_SpreadMachine_VisualSetting V WITH (NOLOCK)
		INNER JOIN #TB_SpreadMachine T ON V.SpreadMachine_Rid = T.RID
		WHERE V.Code = 'First_Bed'

		--SELECT #TB_SpreadMachine='', * FROM #TB_SpreadMachine
		--WHERE isnull(Valid_Status, 0) = 1
		UPDATE S
		SET S.Marker_Width = CONVERT(DECIMAL(18, 4), ST.sys_value2)
		FROM Tb_CutMachine C WITH (NOLOCK)
		INNER JOIN SYSTEM_TABLE ST WITH (NOLOCK) ON ST.SYS_CODE LIKE 'LineBalance_MarkerWidthType%'
			AND C.MarkerWidth_Type = ST.SYS_VALUE
		INNER JOIN #TB_SpreadMachine S ON S.CutMachine_No = C.CutMachine_No

		--SELECT #TB_SpreadMachine1 = ''
		--	,*
		--FROM #TB_SpreadMachine
		IF object_id('tempdb..#Tb_CutMachine') IS NOT NULL
			DROP TABLE #Tb_CutMachine

		SELECT DISTINCT CutMachine_No
			,Marker_Width
			,Is_Small_Order = convert(BIT, 0)
		INTO #Tb_CutMachine
		FROM #TB_SpreadMachine

		UPDATE #Tb_CutMachine
		SET Is_Small_Order = 1
		WHERE CutMachine_No IN (
				SELECT CutMachine_No
				FROM #TB_SpreadMachine
				WHERE Is_Small_Order = 1
				)

		--SELECT * FROM #TB_SpreadMachine
		--IF object_id('tempdb..#temp_TB_Calculate_Act_Cut_Date_ALL') IS NOT NULL
		--	DROP TABLE #temp_TB_Calculate_Act_Cut_Date_ALL
		--SELECT *
		--INTO #temp_TB_Calculate_Act_Cut_Date_ALL
		--FROM TB_Calculate_Act_Cut_Date_ALL
		--WHERE Lot_number_Cur = @Calculate_LotNumber
		IF object_id('tempdb..#TB_Order_Cut_Plan_Date_ALL_Lot') IS NOT NULL
			DROP TABLE #TB_Order_Cut_Plan_Date_ALL_Lot

		SELECT *
		INTO #TB_Order_Cut_Plan_Date_ALL_Lot
		FROM [dbo].[V_TB_Order_Cut_Plan_Date_ALL_Lot]
		WHERE Lot_number_Cur = @Calculate_LotNumber

		IF object_id('tempdb..#TB_Calculate_Inserting_Info') IS NOT NULL
			DROP TABLE #TB_Calculate_Inserting_Info

		SELECT I.*
			,Insert_Type = convert(VARCHAR(5), NULL)
		INTO #TB_Calculate_Inserting_Info
		FROM [dbo].[V_TB_Calculate_Inserting_Info] I
		INNER JOIN V_CICS_Cut_Plan_Hdr H ON H.Mo_No = I.MO_NO
			AND H.Table_No = I.Table_NO
			AND H.Spd_Type = I.Spd_Type

		--WHERE Lot_number_Cur = @Calculate_LotNumber
		--	AND Create_date >= DATEADD(MONTH, - 1, GETDATE())
		--删除已关闭机器的插单数据
		DELETE a
		FROM #TB_Calculate_Inserting_Info a
		INNER JOIN #TB_SpreadMachine b ON a.SpreadMachine_No = b.SpreadMachine_No
		WHERE ISNULL(b.Valid_Status, 0) = 0

		--select #temp_Calculate_Inserting_Info_Current00='', * from #temp_Calculate_Inserting_Info_Current where table_no=6303
		--临时处理改布封床号，修改存在断电保护数据的床号为正在拉，
		IF object_id('tempdb..#V_CICS_Cut_Plan_Roll_Input') IS NOT NULL
			DROP TABLE #V_CICS_Cut_Plan_Roll_Input

		SELECT *
		INTO #V_CICS_Cut_Plan_Roll_Input
		FROM [V_CICS_Cut_Plan_Roll_Input]

		UPDATE a
		SET a.spd_status = 'P'
		FROM #TB_Order_Cut_Plan_Date_ALL_Lot a
		INNER JOIN #V_CICS_Cut_Plan_Roll_Input b ON a.rid = b.rid
		WHERE isnull(a.Spd_Status, '') <> 'P'

		PRINT '1:'

		--缓存上次锁任务
		IF object_id('tempdb..#SPD_Order_Scheduling_Lock') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_Lock

		SELECT S.RID
			,S.Plan_Date
			,S.Ori_Plan_Date
			,S.SpreadMachine_No
			,S.CutMachine_No
			,S.Case_Category
			,S.CaseNo
			,S.SeqNO
			,S.MO_NO
			,S.Spd_Type
			,S.Table_NO
			,S.Color_Code
			,S.Color_Desc
			,S.SO_No
			,S.Batch_No
			,S.Plan_Layer_Qty
			,S.Act_Layer_Qty
			,S.pull_date_Min
			,S.cut_date_Min
			,S.Plan_Pull_Date_Start
			,S.Plan_Pull_Date_End
			,S.Act_Pull_Date_Start
			,S.Act_Pull_Date_End
			,S.Plan_Cut_Date_Start
			,S.Plan_Cut_Date_End
			,S.Act_Cut_Date_Start
			,S.Act_Cut_Date_End
			,S.Used_Length
			,S.Allocate_Length
			,S.Rest_Minute
			,S.Cut_SeqNO
			,S.Can_Cut_Date
			,S.Can_Spread_Date
			,S.Create_Date
			,S.Paper_Sample
			,S.First_Table
			,S.QRTYPE
			,S.Other_Main_Rid
			,S.IS_Last_Cut
			,S.Order_Status
			,S.Order_Status_Type
			,S.AddStatus
			,S.AddStatus_Type
			,S.IS_ALL_Cut
			,S.Priority_Level
			,S.Adjust_Machine_No
			,S.Adjust_Time
			,S.IS_Old_Table
			,S.IS_Merge_Cut
			,S.Merge_Cut_Remark
			,S.[QR_Seq]
			,S.[Spread_Scan_Time]
			,S.[Input_Length]
			,S.Merge_RID
			,S.[Last_Cut_RID]
			,S.Lot_Number_Calculate
			,S.IsLock
			,S.[IsEnough_Material]
			,S.Group_Lot_Number
			,S.Marker_Width
			,S.Adjust_Start_Time
			,S.Is_Small_Order
			,S.Merge_Cut_RID
			,S.IsChao
			,S.Bar_Code
			,S.Is_Cut
			,S.Is_Now
			,S.IsStripe
			,S.IsPadPrint
			,S.IsAbnormal
			,S.Marker_No
			,S.Group_RID
			,S.PadPrinting_Together_RID
		INTO #SPD_Order_Scheduling_Lock
		FROM SPD_Order_Scheduling S WITH (NOLOCK)
		INNER JOIN #TB_SpreadMachine M ON M.SpreadMachine_No = S.SpreadMachine_No
			AND isnull(M.Valid_Status, 0) = 1
		WHERE ISNULL(S.Order_Status_Type, 100) = 2

		--AND isnull(S.Is_Last_Cut, 0) = 0
		PRINT '2:'

		--判断是否后拉且
		--DELETE L
		--FROM #SPD_Order_Scheduling_Lock L
		--INNER JOIN #TB_Order_Cut_Plan_Date_ALL_Lot A ON L.RID <> A.RID
		--	AND L.Batch_No = A.Batch_No
		--	AND L.MO_NO = A.MO_NO
		--WHERE isnull(L.Is_Last_Cut, 0) = 1
		IF object_id('tempdb..#SPD_Order_Scheduling') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling

		SELECT TOP 0 *
		INTO #SPD_Order_Scheduling
		FROM #SPD_Order_Scheduling_Lock
		WHERE 1 = 2

		--select IS_Old_Table from #TB_Order_Cut_Plan_Date_ALL_Lot
		--select IS_Old_Table from #SPD_Order_Scheduling
		INSERT INTO #SPD_Order_Scheduling (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,Other_Main_Rid
			,IS_Last_Cut
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,[QR_Seq]
			,Marker_Width
			,Adjust_Start_Time
			,IsChao
			,Bar_Code
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			)
		SELECT L.RID
			,Plan_Date
			,Ori_Plan_Date = Plan_Date_Old
			,SpreadMachine_No = NULL
			,CutMachine_No = NULL
			,Case_Category = NULL
			,CaseNo = NULL
			,SeqNO = NULL
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty = NULL
			,pull_date_Min = pull_date
			,cut_date_Min = cut_date
			,Plan_Pull_Date_Start = NULL
			,Plan_Pull_Date_End = NULL
			,Act_Pull_Date_Start = NULL
			,Act_Pull_Date_End = NULL
			,Plan_Cut_Date_Start = NULL
			,Plan_Cut_Date_End = NULL
			,Act_Cut_Date_Start = NULL
			,Act_Cut_Date_End = NULL
			,Used_Length
			,Allocate_Length = NULL
			,Rest_Minute = NULL
			,Cut_SeqNO = NULL
			,Can_Cut_Date
			,Can_Spread_Date = NULL
			,Create_Date = GETDATE()
			,Paper_Sample
			,First_Table
			,QRTYPE
			,Other_Main_Rid
			,IS_Last_Cut = CASE 
				WHEN Last_Cut = 'Y'
					THEN 1
				ELSE 0
				END
			,Order_Status = NULL
			,Order_Status_Type = NULL
			,AddStatus = NULL
			,AddStatus_Type = NULL
			,IS_ALL_Cut = CASE 
				WHEN IS_ALL_Cut = 'Y'
					THEN 1
				ELSE 0
				END
			,Priority_Level = NULL
			,Adjust_Machine_No = NULL --调单拉布机
			,Adjust_Time = NULL
			,IS_Old_Table
			,IS_Merge_Cut = CASE 
				WHEN Merge_Cut = 'Y'
					THEN 1
				ELSE 0
				END
			,Merge_Cut_Remark = cut_remk
			,[QR_Seq] = CONVERT(INT, 99)
			,Marker_Width
			,Adjust_Start_Time = NULL
			,IsChao
			,Bar_Code
			,IsStripe = CASE 
				WHEN Action_Type = 'Strip'
					THEN 1
				ELSE 0
				END
			,IsPadPrint = CONVERT(BIT, 0) --CASE WHEN Action_Type = 'Strip' THEN 1 ELSE 0 END
			,IsAbnormal = CASE 
				WHEN Action_Type = 'ExcludeSO_Delete'
					THEN 1
				ELSE 0
				END
			,Marker_No = L.Marker_Name
		FROM #TB_Order_Cut_Plan_Date_ALL_Lot L

		--select #SPD_Order_Scheduling1='', * from #SPD_Order_Scheduling where table_no=7000
		--把已拉的数据加回来 Begin
		IF object_id('tempdb..#V_CICS_Act_Cut_Hdr') IS NOT NULL
			DROP TABLE #V_CICS_Act_Cut_Hdr

		SELECT *
		INTO #V_CICS_Act_Cut_Hdr
		FROM dbo.V_CICS_Act_Cut_Hdr H
		WHERE H.Cut_Date >= DATEADD(HOUR, - 8, GETDATE())

		IF object_id('tempdb..#SPD_Order_Scheduling_ActCut') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_ActCut

		SELECT TOP 0 RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,Other_Main_Rid
			,IS_Last_Cut
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,[QR_Seq]
			,Adjust_Start_Time
		INTO #SPD_Order_Scheduling_ActCut
		FROM #SPD_Order_Scheduling
		WHERE 1 = 2

		PRINT '1111'

		INSERT INTO #SPD_Order_Scheduling_ActCut (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,Other_Main_Rid
			,IS_Last_Cut
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,[QR_Seq]
			,Adjust_Start_Time
			)
		SELECT RID = H.RID
			,Plan_Date
			,Ori_Plan_Date = Plan_Date
			,SpreadMachine_No = Machine_No
			,CutMachine_No = M.CutMachine_NO
			,Case_Category = NULL
			,CaseNo = NULL
			,SeqNO = 0
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code = NULL
			,Color_Desc = NULL
			,SO_No = NULL
			,Batch_No = NULL
			,Plan_Layer_Qty = 0
			,Act_Layer_Qty = 0
			,pull_date_Min = 0
			,cut_date_Min = 0
			,Plan_Pull_Date_Start = Cut_Date_Start
			,Plan_Pull_Date_End = Cut_date
			,Act_Pull_Date_Start = Cut_Date_Start
			,Act_Pull_Date_End = Cut_date
			,Plan_Cut_Date_Start = Cut_date
			,Plan_Cut_Date_End = NULL
			,Act_Cut_Date_Start = Cut_date
			,Act_Cut_Date_End = NULL
			,Used_Length = NULL
			,Allocate_Length = NULL
			,Rest_Minute = NULL
			,Cut_SeqNO = 0
			,Can_Cut_Date = NULL
			,Can_Spread_Date = NULL
			,Create_Date = GETDATE()
			,Paper_Sample
			,First_Table
			,QRTYPE = NULL
			,Other_Main_Rid
			,IS_Last_Cut = NULL
			,Order_Status = 'A'
			,Order_Status_Type = 0
			,AddStatus = 'C'
			,AddStatus_Type = NULL
			,IS_ALL_Cut = NULL
			,Priority_Level = NULL
			,Adjust_Machine_No = NULL
			,Adjust_Time = NULL
			,IS_Old_Table = NULL
			,IS_Merge_Cut = NULL
			,Merge_Cut_Remark = NULL
			,[QR_Seq] = NULL
			,Adjust_Start_Time = NULL
		FROM #V_CICS_Act_Cut_Hdr H
		LEFT JOIN #TB_SpreadMachine M ON M.SpreadMachine_No = H.Machine_No

		DELETE
		FROM #SPD_Order_Scheduling_ActCut
		WHERE SpreadMachine_No IN (
				SELECT SpreadMachine_No
				FROM #TB_SpreadMachine
				WHERE ISNULL(Valid_Status, 0) = 0
				)
			OR RID IN (
				SELECT RID
				FROM #SPD_Order_Scheduling
				)

		--UPDATE a
		--SET a.Act_Cut_Date_End = b.Create_date
		--	,a.Plan_Cut_Date_End = b.Create_date
		--FROM #SPD_Order_Scheduling_ActCut a
		--INNER JOIN dbo.V_CICS_Act_Cut_Emp b ON a.rid = b.rid
		--WHERE b.Op_Type = '2'
		--AND a.Act_Cut_Date_End IS NULL
		INSERT INTO #SPD_Order_Scheduling (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,Other_Main_Rid
			,IS_Last_Cut
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,[QR_Seq]
			,Adjust_Start_Time
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty --= Act_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,Other_Main_Rid
			,IS_Last_Cut
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,[QR_Seq]
			,Adjust_Start_Time = NULL
		FROM #SPD_Order_Scheduling_ActCut

		--select #SPD_Order_Scheduling2='', * from #SPD_Order_Scheduling where table_no=7000
		--把已拉的数据加回来 End
		--增加批次锁定
		UPDATE S
		SET S.[Lot_Number_Calculate] = @Calculate_LotNumber
		FROM #SPD_Order_Scheduling S

		--SELECT *
		UPDATE S
		SET S.Group_Lot_Number = ISNULL(DTL.Group_Lot_Number, '')
		FROM #SPD_Order_Scheduling S
		INNER JOIN V_CICS_Cut_Plan_Dtl Dtl ON S.RID = Dtl.RID

		--计算合拉
		IF object_id('tempdb..#SPD_Order_Scheduling_Merge') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_Merge

		SELECT Merge_idx = ROW_NUMBER() OVER (
				ORDER BY Merge_Cut_Remark
				)
			,*
		INTO #SPD_Order_Scheduling_Merge
		FROM #SPD_Order_Scheduling
		WHERE isnull(Merge_Cut_Remark, '') <> ''

		--SELECT *
		--FROM #SPD_Order_Scheduling_Merge
		--SELECT *
		--FROM dbo.uf_StrSplit('1000/1002/1006', '/')
		DECLARE @Merge_idx INT = 1
			,@SO_No VARCHAR(100) = ''
			,@Batch_No NVARCHAR(200) = ''
			,@RID VARCHAR(50) = ''
			,@Merge_Cut_Remark VARCHAR(1000) = ''
			,@Merge_RID VARCHAR(50) = ''
		DECLARE @Merge_Table TABLE (Table_No VARCHAR(20) NULL)

		--WHILE EXISTS (
		--		SELECT TOP 1 1
		--		FROM #SPD_Order_Scheduling_Merge
		--		WHERE Merge_idx >= @Merge_idx
		--		)
		--BEGIN
		--	SELECT @SO_No = ''
		--		,@Batch_No = ''
		--		,@RID = ''
		--		,@Merge_Cut_Remark = ''
		--		,@Merge_RID = CONVERT(VARCHAR(50), NEWID())
		--	SELECT TOP 1 @SO_No = SO_NO
		--		,@Batch_No = Batch_No
		--		,@RID = RID
		--		,@Merge_Cut_Remark = Merge_Cut_Remark
		--	FROM #SPD_Order_Scheduling_Merge
		--	WHERE Merge_idx = @Merge_idx
		--	SELECT @Merge_idx = @Merge_idx + 1
		--	UPDATE S
		--	SET S.Merge_RID = @Merge_RID
		--	FROM #SPD_Order_Scheduling S
		--	WHERE S.RID = @RID
		--	IF ISNULL(@Merge_Cut_Remark, '') <> ''
		--	BEGIN
		--		INSERT INTO @Merge_Table (Table_No)
		--		SELECT string
		--		FROM dbo.uf_StrSplit(@Merge_Cut_Remark, '/')
		--		UPDATE S
		--		SET S.Merge_RID = @Merge_RID
		--		FROM #SPD_Order_Scheduling S
		--		INNER JOIN @Merge_Table M ON CONVERT(VARCHAR(20), S.TABLE_NO) = M.TABLE_NO
		--		WHERE S.SO_NO = @SO_NO
		--			AND Batch_No = @Batch_No
		--	END
		--END
		--SELECT #SPD_Order_Scheduling1659 = ''
		--	,*
		--FROM #SPD_Order_Scheduling
		--更新插单信息
		----更新实裁时间
		UPDATE a
		SET a.Act_Pull_Date_End = b.Cut_Date
			,a.Act_Pull_Date_Start = b.Cut_Date_Start
			,a.Plan_Pull_Date_End = b.Cut_Date
			,a.Plan_Pull_Date_Start = b.Cut_Date_Start
			,a.Act_Cut_Date_Start = b.Cut_Date
			,a.Act_Layer_Qty = c.Act_Layer_Qty
			,a.Plan_Layer_Qty = c.Act_Layer_Qty
			,a.Order_Status = 'A'
			,A.Order_Status_Type = 0
			,A.SpreadMachine_No = B.Machine_No
			,A.RID = B.RID
			,a.CutMachine_No = M.CutMachine_NO
			,a.Batch_NO = C.Batch_No
			,A.Color_Code = isnull(c.Color_Code, '')
		FROM #SPD_Order_Scheduling a
		INNER JOIN #V_CICS_Act_Cut_Hdr b ON a.MO_NO = b.MO_NO
			AND A.Table_No = b.Table_No
			AND A.SPD_TYPE = B.SPD_TYPE
		INNER JOIN dbo.V_CICS_Act_Cut_Dtl c ON b.rid = c.rid
		LEFT JOIN #TB_SpreadMachine M WITH (NOLOCK) ON M.SpreadMachine_No = B.Machine_No

		--WHERE (a.Act_Pull_Date_End IS NULL)
		--SELECT *
		UPDATE S
		SET S.SO_NO = SO.So_No
		FROM #SPD_Order_Scheduling S
		INNER JOIN V_CICS_So_Mo_Ref SO ON SO.Mo_No = S.Mo_No
		WHERE ISNULL(S.SO_NO, '') = ''

		UPDATE a
		SET A.Act_Cut_Date_End = b.Create_date
			,A.Plan_Cut_Date_End = b.Create_date
			,A.Is_Cut = 1
		FROM #SPD_Order_Scheduling a
		INNER JOIN dbo.V_CICS_Act_Cut_Emp b ON a.rid = b.rid
		WHERE b.Op_Type = '2'

		--捆条不计算裁剪时间
		UPDATE a
		SET A.Is_Cut = 1
			,A.Act_Cut_Date_End = A.Act_Cut_Date_Start
			,A.Plan_Cut_Date_End = a.Plan_Cut_Date_Start
		FROM #SPD_Order_Scheduling a
		WHERE (
				Spd_Type LIKE 'C%'
				OR Spd_Type = 'W'
				)
			AND Order_Status_Type = 0
			AND ISNULL(IS_CUT, 0) = 0

		--AND a.Act_Cut_Date_End IS NULL
		--SELECT *
		--更新QR顺序
		UPDATE S
		SET S.QR_Seq = convert(INT, isnull(ST.SYS_VALUE, '99'))
		FROM #SPD_Order_Scheduling S
		LEFT JOIN System_Table ST ON ST.SYS_Code = 'QRType'
			AND S.QRTYPE = ST.Sys_Sdescription

		UPDATE #SPD_Order_Scheduling
		SET plan_date = CASE 
				WHEN plan_date <= @Work_Date
					THEN @Work_Date
				ELSE plan_date
				END

		--判断是否旧单
		UPDATE #SPD_Order_Scheduling
		SET IS_Old_Table = CASE 
				WHEN plan_date > Ori_Plan_Date
					THEN 1
				ELSE 0
				END

		----优先L单
		--UPDATE S
		--SET S.Priority_Level = 0
		--FROM #SPD_Order_Scheduling S
		--WHERE Spd_Type LIKE 'L%'
		--	AND S.Priority_Level IS NULL
		----优先前一天首床 
		--UPDATE S
		--SET S.Priority_Level = 1
		--FROM #SPD_Order_Scheduling S
		--WHERE IS_OLD_TABLE = 1
		--	AND First_Table = 1
		--	AND S.Priority_Level IS NULL
		----优先当天首床
		--UPDATE S
		--SET S.Priority_Level = 2
		--FROM #SPD_Order_Scheduling S
		--WHERE First_Table = 1
		--	AND S.Priority_Level IS NULL
		--	AND Ori_Plan_Date = @Work_Date
		----优先前一天计划未完成的SQR单
		--UPDATE S
		--SET S.Priority_Level = 3
		--FROM #SPD_Order_Scheduling S
		--WHERE IS_OLD_TABLE = 1
		--	AND QR_Seq = 0
		--	AND S.Priority_Level IS NULL
		----优先前一天计划未完成的QR单
		--UPDATE S
		--SET S.Priority_Level = 4
		--FROM #SPD_Order_Scheduling S
		--WHERE IS_OLD_TABLE = 1
		--	AND QR_Seq = 1
		--	AND S.Priority_Level IS NULL
		----优先当天计划的SQR
		--UPDATE S
		--SET S.Priority_Level = 5
		--FROM #SPD_Order_Scheduling S
		--WHERE QR_Seq = 0
		--	AND Ori_Plan_Date = @Work_Date
		--	AND S.Priority_Level IS NULL
		----优先前一天计划未完成的Normal单
		--UPDATE S
		--SET S.Priority_Level = 6
		--FROM #SPD_Order_Scheduling S
		--WHERE QR_Seq = 2
		--	AND IS_OLD_TABLE = 1
		--	AND S.Priority_Level IS NULL
		----优先当天计划的QR单
		--UPDATE S
		--SET S.Priority_Level = 7
		--FROM #SPD_Order_Scheduling S
		--WHERE QR_Seq = 1
		--	AND Ori_Plan_Date = @Work_Date
		--	AND S.Priority_Level IS NULL
		----优先当天计划的Normal单
		--UPDATE S
		--SET S.Priority_Level = 8
		--FROM #SPD_Order_Scheduling S
		--WHERE S.Priority_Level IS NULL
		--	AND Ori_Plan_Date = @Work_Date
		IF object_id('tempdb..#Job_Seq_Schedule_Priority') IS NOT NULL
			DROP TABLE #Job_Seq_Schedule_Priority

		SELECT idx = ROW_NUMBER() OVER (
				ORDER BY Priority_Seq
				)
			,Script = replace(replace(Script, '{Priority_Level}', Priority_Seq), '{Work_Date}', convert(VARCHAR(20), @Work_Date, 23))
		INTO #Job_Seq_Schedule_Priority
		FROM Job_Seq_Schedule_Priority

		DECLARE @Priority_Index INT = 1
			,@Priority_Script NVARCHAR(MAX) = ''

		--按维护的优先级标记等级 Damon gu 2025/03/18
		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #Job_Seq_Schedule_Priority
				WHERE idx >= @Priority_Index
				)
		BEGIN
			SELECT TOP 1 @Priority_Script = Script
			FROM #Job_Seq_Schedule_Priority
			WHERE idx = @Priority_Index

			SELECT @Priority_Index = @Priority_Index + 1

			PRINT '@Priority_Index=' + convert(VARCHAR(10), @Priority_Index) + ',@Priority_Script=' + isnull(@Priority_Script, '')

			EXEC (@Priority_Script)
		END

		UPDATE S
		SET S.Priority_Level = 99
		FROM #SPD_Order_Scheduling S
		WHERE S.Priority_Level IS NULL

		--删掉停用床
		--DELETE S
		UPDATE S
		SET S.SpreadMachine_No = NULL
			,S.CutMachine_No = NULL
		FROM #SPD_Order_Scheduling S
		INNER JOIN #TB_SpreadMachine M ON M.SpreadMachine_No = S.SpreadMachine_No
			AND isnull(M.Valid_Status, 0) = 0

		--更新拉布扫条码时间
		UPDATE S
		SET S.[Spread_Scan_Time] = H.cut_date_start
			,S.Order_Status = 'B'
			,S.Order_Status_Type = 1
			,S.SpreadMachine_No = H.Machine_No
			,S.CutMachine_No = M.CutMachine_No
			,S.Plan_Date = @Work_Date
		FROM V_CICS_Cut_Plan_Hdr H
		INNER JOIN #SPD_Order_Scheduling S ON S.MO_NO = H.MO_NO
			AND S.TABLE_NO = H.TABLE_NO
			AND S.SPD_Type = H.SPD_Type
		LEFT JOIN #TB_SpreadMachine M ON M.SpreadMachine_No = H.Machine_No
		--AND isnull(M.Valid_Status, 0) = 1
		WHERE H.Spd_Status = 'P'

		--AND ISNULL(S.Order_Status, '') = ''
		--更新上次计算锁单状态
		--SELECT *
		UPDATE S
		SET S.Order_Status = 'C'
			,S.Order_Status_Type = 2
			,S.SpreadMachine_No = L.SpreadMachine_No
			,S.CutMachine_No = L.CutMachine_No
			,S.SeqNO = L.SeqNO
		FROM #SPD_Order_Scheduling S
		INNER JOIN #SPD_Order_Scheduling_Lock L ON L.MO_NO = S.MO_NO
			AND L.TABLE_NO = S.TABLE_NO
			AND L.SPD_TYPE = S.SPD_TYPE
		WHERE ISNULL(S.Order_Status, '') = ''

		--其他统一更新99
		UPDATE S
		SET S.Order_Status_Type = 99
		FROM #SPD_Order_Scheduling S
		WHERE ISNULL(S.Order_Status, '') = ''

		UPDATE S
		SET S.Adjust_Machine_No = I.SpreadMachine_No
			,Adjust_Time = Limit_Completed_Time
			,Adjust_Start_Time = Limit_Start_Time
			--,S.SpreadMachine_No = I.SpreadMachine_No
			,S.CutMachine_No = M.CutMachine_No
			--,S.Order_Status = CASE 
			--	WHEN Limit_Completed_Time <= dbo.fn_CCT_GetEndTime(dateadd(SECOND, pull_date_Min * 60.00, ISNULL(GETDATE(), GETDATE())))
			--		THEN 'D'
			--	ELSE NULL
			--	END
			,Order_Status_Type = CASE 
				WHEN Limit_Completed_Time <= dbo.fn_CCT_GetEndTimeNew(dateadd(SECOND, pull_date_Min * 60.00, ISNULL(GETDATE(), GETDATE())),pull_date_Min)
					THEN 3
				ELSE NULL
				END
		FROM #SPD_Order_Scheduling S
		INNER JOIN #TB_Calculate_Inserting_Info I ON S.MO_NO = I.MO_NO
			AND S.Table_No = I.Table_No
			AND S.Spd_Type = I.Spd_Type
		LEFT JOIN #TB_SpreadMachine M WITH (NOLOCK) ON M.SpreadMachine_No = S.SpreadMachine_No
		WHERE ISNULL(S.Order_Status_Type, 99) >= 2

		--SELECT #SPD_Order_Scheduling1 = ''
		--	,*
		--FROM #SPD_Order_Scheduling
		--WHERE RID = '2584919D-E57C-49C4-B771-8D26C13680E7'
		UPDATE #SPD_Order_Scheduling
		SET Order_Status = 'D'
			,Plan_Date = @Work_Date
		WHERE Order_Status_Type = 3

		--更新已锁顶裁剪机
		UPDATE S
		SET S.CutMachine_No = M.CutMachine_NO
		FROM #SPD_Order_Scheduling S
		INNER JOIN #TB_SpreadMachine M WITH (NOLOCK) ON M.SpreadMachine_No = S.SpreadMachine_No
			AND ISNULL(M.Valid_Status, 0) = 1
		INNER JOIN Tb_CutMachine C WITH (NOLOCK) ON C.CutMachine_No = M.CutMachine_NO
			AND ISNULL(C.Valid_Status, 0) = 1
		WHERE ISNULL(S.CutMachine_No, '') = ''

		--SELECT * FROM Tb_CutMachine
		--SELECT * FROM TB_SpreadMachine
		--计算布料
		IF object_id('tempdb..#SO_Batch_No') IS NOT NULL
			DROP TABLE #SO_Batch_No

		SELECT DISTINCT SO_NO
			,Batch_No
		INTO #SO_Batch_No
		FROM #SPD_Order_Scheduling
		WHERE Order_Status_Type > 0

		IF object_id('tempdb..#V_CICS_Fab_Release_WIP') IS NOT NULL
			DROP TABLE #V_CICS_Fab_Release_WIP

		SELECT W.*
			,Group_Lot_Number = CONVERT(VARCHAR(50), NULL)
		INTO #V_CICS_Fab_Release_WIP
		FROM [dbo].[V_CICS_Fab_Release_WIP] W
		INNER JOIN #SO_Batch_No S ON W.SO_NO = S.SO_NO
			--AND W.Batch_No = S.Batch_No
			AND 1 = [dbo].[fn_CCT_CheckBatchNoIsContain](S.Batch_No, W.Batch_No)

		--更新色组
		--SELECT *
		UPDATE W
		SET W.Group_Lot_Number = G.Group_Lot_Number
		FROM #V_CICS_Fab_Release_WIP W
		INNER JOIN [dbo].[V_CICS_Inspestion_Batch_Group] G ON W.Batch_no = G.Batch_no
			AND W.So_No = G.So_No
			AND W.Roll_No = G.Roll_No

		--SELECT *
		--FROM #SPD_Order_Scheduling
		DECLARE @index INT = 1
			,@Used_Length DECIMAL(18, 4) = NULL
			,@Allocate_Length DECIMAL(18, 4) = NULL
			--Last_Leng_Qty
			,@Last_Leng_Qty DECIMAL(18, 4) = NULL
			,@Barcode_No VARCHAR(100) = NULL
			,@End_Date DATETIME = NULL
			,@Sub_index INT = 20
			,@Order_Status_Type INT = 0
			,@Group_Lot_Number VARCHAR(50) = ''

		IF object_id('tempdb..#SPD_Order_Scheduling_idx') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_idx

		SELECT idx2 = ROW_NUMBER() OVER (
				PARTITION BY rid ORDER BY rid
				)
			,idx = row_number() OVER (
				ORDER BY Order_Status_Type
					,[Priority_Level]
					,Ori_Plan_Date
					,IS_Last_Cut
					,QR_Seq
					,table_no
				)
			,*
		INTO #SPD_Order_Scheduling_idx
		FROM #SPD_Order_Scheduling --order by Priority_Level

		--Damon gu 2025-09-30 更新PadPrinting单
		IF EXISTS (
				SELECT TOP 1 1
				FROM #TB_SpreadMachine T
				WHERE ISNULL(T.IsPadPrint, 0) = 1
				)
		BEGIN
			UPDATE S
			SET S.IsPadPrint = 1
			FROM #SPD_Order_Scheduling_idx S
			INNER JOIN [dbo].[v_MES_Printing_Info_VAP] P ON P.Category_Code = 'Pad Printing'
				AND P.SO_NO = S.SO_No
		END

		--WHERE EXISTS(SELECT TOP 1 1 FROM #TB_SpreadMachine T WHERE ISNULL(T.IsPadPrint,0) = 1 )
		UPDATE S
		SET S.SpreadMachine_No = 'Fry'
			,S.CutMachine_No = 'Fry-CUT'
		FROM #SPD_Order_Scheduling_idx S
		WHERE isnull(IsChao, 0) = 1
			AND ISNULL(Order_Status_Type, 0) > 1

		DELETE
		FROM #SPD_Order_Scheduling_idx
		WHERE idx2 > 1

		DECLARE @Small_Order_Count INT = 4000

		BEGIN TRY
			SELECT @Small_Order_Count = convert(INT, SYS_VALUE)
			FROM System_Table WITH (NOLOCK)
			WHERE SYS_CODE = 'Small_Order_Count'
				AND Sys_Sdescription = 'Small_Order_Count'
		END TRY

		BEGIN CATCH
		END CATCH

		--更新小单标识
		UPDATE S
		SET S.Is_Small_Order = 1
		FROM #SPD_Order_Scheduling_idx S
		INNER JOIN V_ETS_SCZZD ZD ON S.MO_NO = ZD.ZDCODE
		WHERE ZD.MY_COUNT <= @Small_Order_Count

		--SELECT @JsonStr = ''
		--SELECT @JsonStr = (
		--		SELECT *
		--		FROM #SPD_Order_Scheduling_idx
		--		FOR JSON PATH
		--		)
		----DECLARE @Cut_Action_Message NVARCHAR(MAX) = N'计算物料前'
		--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
		--	,@Action_ID = 'Job'
		--	,@Action_Type = 'BeforeCalculateMaterials'
		--	,@Action_Message = N'计算物料前'
		SELECT @Action_ID = 'Job'
			,@Action_Type = 'BeforeCalculateMaterials'
			,@Action_Message = N'计算物料前'

		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = @Action_ID
			,Action_Type = @Action_Type
			,Action_Date = GETDATE()
			,Action_Message = @Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM #SPD_Order_Scheduling_idx

		DECLARE @Quit_Index INT = 1
			,@Trolley_Code VARCHAR(50) = ''
		DECLARE @Cut_Action_Message NVARCHAR(MAX) = N''
			,@Materials_RID VARCHAR(50) = ''

		--计算物料是否足够
		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_idx
				WHERE idx >= @index
				)
		BEGIN
			PRINT N'计算物料是否足够'

			SELECT @Allocate_Length = 0
				,@SO_No = ''
				,@Batch_No = ''
				,@RID = ''
				,@Used_Length = 0
				,@Sub_index = 20
				,@Order_Status_Type = 0
				,@Allocate_Length = 0
				,@End_Date = NULL
				,@Group_Lot_Number = ''
				,@Materials_RID = CONVERT(VARCHAR(50), NEWID())

			SELECT TOP 1 @SO_No = SO_No
				,@Batch_No = Batch_No
				,@RID = RID
				,@Used_Length = Used_Length
				,@Order_Status_Type = Order_Status_Type
				,@Group_Lot_Number = Group_Lot_Number
			FROM #SPD_Order_Scheduling_idx
			WHERE idx = @index

			SELECT @index = @index + 1

			IF @Order_Status_Type <= 0 --已完成不算
			BEGIN
				CONTINUE;
			END

			IF @Order_Status_Type = 1 -- 正在拉
			BEGIN
				--SELECT TOP 10 * FROM V_CICS_Cut_Plan_Roll_Input
				SELECT @Allocate_Length = SUM(ISNULL(Used_Length, 0))
				FROM #V_CICS_Cut_Plan_Roll_Input
				WHERE RID = @RID

				SELECT @Used_Length = @Used_Length - ISNULL(@Allocate_Length, 0)

				UPDATE #SPD_Order_Scheduling_idx
				SET [Input_Length] = @Allocate_Length
				WHERE RID = @RID
			END

			SELECT @Quit_Index = 1

			WHILE @Used_Length > 0
				--AND @Sub_index > 0
				AND @Quit_Index <= 20000 --防止死循环
			BEGIN
				PRINT N'计算物料是否足够2'

				SELECT @Quit_Index = @Quit_Index + 1

				SELECT @Barcode_No = ''
					,@Last_Leng_Qty = 0
					,@End_Date = NULL
					,@Trolley_Code = ''

				--SELECT @Sub_index = @Sub_index - 1;
				SELECT TOP 1 @Barcode_No = Barcode_No
					,@Last_Leng_Qty = ISNULL(Last_Leng_Qty, 0)
					,@End_Date = End_Date
					,@Trolley_Code = Pallet_BarCode
				FROM #V_CICS_Fab_Release_WIP
				WHERE SO_NO = @SO_No
					AND 1 = [dbo].[fn_CCT_CheckBatchNoIsContain](@Batch_No, BatCh_No) --BatCh_No = @Batch_No
					AND ISNULL(Last_Leng_Qty, 0) > 0
					AND ISNULL(Group_Lot_Number, '') = CASE 
						WHEN ISNULL(@Group_Lot_Number, '') = ''
							THEN ISNULL(Group_Lot_Number, '')
						ELSE ISNULL(@Group_Lot_Number, '')
						END
				ORDER BY End_Date
					,Last_Leng_Qty

				PRINT '@Barcode_No=' + ISNULL(@Barcode_No, '') + ',@Last_Leng_Qty' + CONVERT(VARCHAR(30), ISNULL(@Last_Leng_Qty, 0.00)) + ',@RID=' + ISNULL(@RID, '')

				IF @Used_Length >= @Last_Leng_Qty
				BEGIN
					SELECT @Used_Length = @Used_Length - @Last_Leng_Qty

					UPDATE #V_CICS_Fab_Release_WIP
					SET Last_Leng_Qty = 0
					WHERE Barcode_No = @Barcode_No --用完
				END
				ELSE
				BEGIN
					SELECT @Last_Leng_Qty = @Last_Leng_Qty - @Used_Length

					SELECT @Used_Length = 0

					UPDATE #V_CICS_Fab_Release_WIP
					SET Last_Leng_Qty = @Last_Leng_Qty
					WHERE Barcode_No = @Barcode_No --还剩余
				END

				UPDATE #SPD_Order_Scheduling_idx
				SET Allocate_Length = Used_Length - @Used_Length
					,Can_Spread_Date = @End_Date
				WHERE RID = @RID

				--SELECT @JsonStr = ''
				--SELECT @JsonStr = (
				--		SELECT *
				--		FROM #SPD_Order_Scheduling_idx
				--		WHERE RID = @RID
				--		FOR JSON PATH
				--		)
				SELECT @Cut_Action_Message = N'@Materials_RID=' + ISNULL(@Materials_RID, '') + N',@Quit_Index=' + CONVERT(VARCHAR(10), @Quit_Index) + N',@Used_Length=' + ISNULL(CONVERT(VARCHAR(20), @Used_Length), '') + N',找到物料@Trolley_Code=' + ISNULL(@Trolley_Code, '') + N',@Barcode_No=' + ISNULL(@Barcode_No, '') + N',@Last_Leng_Qty=' + CONVERT(VARCHAR(50), ISNULL(@Last_Leng_Qty, 0)) + N',@End_Date=' + ISNULL(CONVERT(VARCHAR(30), @End_Date, 21), '') + ',@Group_Lot_Number=' + ISNULL(@Group_Lot_Number, '') + ',@SO_No=' + ISNULL(@SO_No, '') + ',@Batch_No=' + ISNULL(@Batch_No, '')

				--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
				--	,@Action_ID = 'Job'
				--	,@Action_Type = 'CalculateMaterials'
				--	,@Action_Message = @Cut_Action_Message
				SELECT @Action_ID = 'Job'
					,@Action_Type = 'CalculateMaterials'
					,@Action_Message = @Cut_Action_Message

				INSERT INTO #SPD_Order_Scheduling_log (
					RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID
					,Action_Type
					,Action_Date
					,Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
					)
				SELECT RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID = @Action_ID
					,Action_Type = @Action_Type
					,Action_Date = GETDATE()
					,Action_Message = @Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No = SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx
				WHERE RID = @RID

				IF ISNULL(@Barcode_No, '') = '' --没找到，结束
				BEGIN
					BREAK;
				END
			END
		END

		SELECT @Cut_Action_Message = N'初步分配裁剪机前处理相同MO缸号'

		DECLARE @Priority_Level_Min INT = 0
			,@Plan_Date_Min DATE = NULL
			,@CutMachine_No VARCHAR(50) = ''
			,@CutMachine_No_SO_Batch VARCHAR(50) = ''
			,@CutMachine_No_Adjust VARCHAR(50) = ''
			,@CutMachine_No_Rob VARCHAR(50) = ''
			,@CutMachine_No_MaxMins VARCHAR(50) = ''
			,@Cut_SeqNO INT = 1
			,@print_Msg NVARCHAR(MAX) = ''
			,@Adjust_Machine_No VARCHAR(50) = ''
			,@CutMachine_idx INT = 0
			,@Marker_Width DECIMAL(18, 4) = 0
			,@Is_Small_Order BIT = 0

		UPDATE S
		SET S.Cut_SeqNO = New_Cut_SeqNo
		FROM #SPD_Order_Scheduling_idx S
		INNER JOIN (
			SELECT New_Cut_SeqNo = ROW_NUMBER() OVER (
					PARTITION BY CutMachine_No ORDER BY Spread_Scan_Time
					)
				,RID
			FROM #SPD_Order_Scheduling_idx
			WHERE isnull(CutMachine_No, '') <> ''
				AND Spread_Scan_Time IS NOT NULL
			) D ON D.RID = S.RID

		IF object_id('tempdb..#MES_CuttingMachineMap') IS NOT NULL
			DROP TABLE #MES_CuttingMachineMap

		SELECT *
		INTO #MES_CuttingMachineMap
		FROM [dbo].[V_MES_CuttingMachineMap]

		IF object_id('tempdb..#TB_SpreadMachine_Count') IS NOT NULL
			DROP TABLE #TB_SpreadMachine_Count

		SELECT CutMachine_NO
			,Spread_Count = ISNULL(SUM(D.SpreadMachine_Count), 1)
			,idx = convert(INT, 0)
		INTO #TB_SpreadMachine_Count
		FROM #TB_SpreadMachine S
		LEFT JOIN (
			SELECT SpreadMachine_No
				,SpreadMachine_Count = CONVERT(DECIMAL(18, 2), 1.00 / COUNT(1))
			FROM #MES_CuttingMachineMap
			GROUP BY SpreadMachine_No
			) D ON S.SpreadMachine_No = D.SpreadMachine_No
		--WHERE isnull(Valid_Status, 0) = 1
		GROUP BY CutMachine_NO

		IF object_id('tempdb..#TB_CutMachine_Count') IS NOT NULL
			DROP TABLE #TB_CutMachine_Count

		SELECT SpreadMachine_No
			,CutMachine_Count = COUNT(1)
		INTO #TB_CutMachine_Count
		FROM [dbo].[V_MES_CuttingMachineMap]
		GROUP BY SpreadMachine_No

		INSERT INTO LOGS (
			RID
			,UserID
			,ActionTime
			,FullURL
			,Source
			,StackTrace
			,Message
			,LogType
			)
		SELECT RID = CONVERT(VARCHAR(50), NEWID())
			,UserID = ''
			,ActionTime = GETDATE()
			,FullURL = 'TB_SpreadMachine_Count'
			,Source = 'P_Task_Calculate'
			,StackTrace = ''
			,Message = (
				SELECT *
				FROM #TB_SpreadMachine_Count
				FOR JSON PATH
				)
			,LogType = '10'

		UPDATE c
		SET c.idx = d.idx1
		FROM #TB_SpreadMachine_Count c
		INNER JOIN (
			SELECT idx1 = ROW_NUMBER() OVER (
					ORDER BY CutMachine_NO
					)
				,*
			FROM #TB_SpreadMachine_Count
			) d ON d.CutMachine_NO = c.CutMachine_NO

		--判断是否够物料
		UPDATE #SPD_Order_Scheduling_idx
		SET [IsEnough_Material] = CASE 
				WHEN (
						Can_Spread_Date IS NOT NULL
						AND Can_Spread_Date <= GETDATE()
						AND isnull(Allocate_Length, 0) >= isnull(Used_Length, 0)
						)
					OR isnull(First_Table, 0) = 1
					OR isnull(IS_Old_Table, 0) = 1
					THEN 1
				ELSE 0
				END

		--SELECT *,A=isnull(Order_Status_Type, 99)
		--		,B=PLAN_DATE
		--		,C=[IsEnough_Material] 
		--		,D=CASE 
		--			WHEN isnull(Paper_Sample, '') <> ''
		--				THEN 0
		--			ELSE 1
		--			END
		--		,E=[Priority_Level]
		--		,F=(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
		--		,G=isnull(IS_Last_Cut, 0)
		--	FROM #SPD_Order_Scheduling_idx
		--	WHERE isnull(CutMachine_No, '') = ''
		--		--AND Priority_Level = @Priority_Level_Min
		--		--AND Plan_Date = @Plan_Date_Min
		--	and Batch_No='JA2500908A'
		--	ORDER BY isnull(Order_Status_Type, 99)
		--		,PLAN_DATE
		--		,[IsEnough_Material] DESC
		--		,CASE 
		--			WHEN isnull(Paper_Sample, '') <> ''
		--				THEN 0
		--			ELSE 1
		--			END
		--		,[Priority_Level]
		--		--,case when (isnull(Used_Length, 0) - isnull(Allocate_Length, 0))>0 then 1
		--		,isnull(IS_Last_Cut, 0)
		--return;
		--SELECT @JsonStr = ''
		--SELECT @JsonStr = (
		--		SELECT *
		--		FROM #SPD_Order_Scheduling_idx
		--		FOR JSON PATH
		--		)
		--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
		--	,@Action_ID = 'Job'
		--	,@Action_Type = 'BeforeAllocatedCut'
		--	,@Action_Message = N'分配裁剪机前'
		SELECT @Action_ID = 'Job'
			,@Action_Type = 'BeforeAllocatedCut'
			,@Action_Message = N'分配裁剪机前'

		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = @Action_ID
			,Action_Type = @Action_Type
			,Action_Date = GETDATE()
			,Action_Message = @Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM #SPD_Order_Scheduling_idx

		--WHERE RID = @RID
		DECLARE @Same_So_Batch_RID VARCHAR(50) = ''
			,@IsStripe BIT = 0
			,@IsPadPrint BIT = 0
			,@IsAbnormal BIT = 0
			,@IsFirstTable BIT = 0

		SELECT @Quit_Index = 1

		--分配裁剪机
		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_idx
				WHERE isnull(CutMachine_No, '') = ''
				)
			AND @Quit_Index <= 20000
		BEGIN
			PRINT N'分配裁剪机'

			SELECT @Quit_Index = @Quit_Index + 1

			SELECT @rid = ''
				,@Plan_Date_Min = NULL
				,@CutMachine_No = ''
				,@CutMachine_No_SO_Batch = ''
				,@CutMachine_No_Adjust = ''
				,@CutMachine_No_Rob = ''
				--,@CutMachine_No_MaxMins = ''
				,@Cut_SeqNO = 1
				,@print_Msg = ''
				,@Adjust_Machine_No = ''
				,@SO_No = ''
				,@Batch_No = ''
				,@CutMachine_idx = 0
				,@Marker_Width = 0
				,@Is_Small_Order = 0
				,@MO_NO = ''
				,@Same_So_Batch_RID = ''
				,@IsStripe = 0
				,@IsPadPrint = 0
				,@IsAbnormal = 0
				,@IsFirstTable = 0

			SELECT TOP 1 @Plan_Date_Min = Plan_Date
				,@Priority_Level_Min = Priority_Level
			FROM #SPD_Order_Scheduling_idx
			WHERE isnull(CutMachine_No, '') = ''
			ORDER BY Plan_Date
				,Priority_Level

			IF object_id('tempdb..#Pre_Same_MO_Batch') IS NOT NULL
				DROP TABLE #Pre_Same_MO_Batch

			SELECT DISTINCT CutMachine_No
				,MO_NO
				,Batch_No
			--,Cut_SeqNO
			INTO #Pre_Same_MO_Batch
			FROM #SPD_Order_Scheduling_idx
			WHERE ISNULL(CutMachine_No, '') <> ''

			SELECT TOP 1 @rid = rid
				,@Adjust_Machine_No = Adjust_Machine_No
				,@SO_No = SO_No
				,@Batch_No = Batch_No
				,@Marker_Width = ISNULL(Marker_Width, 0)
				,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
				,@MO_NO = MO_NO
				,@IsStripe = IsStripe
				,@IsPadPrint = IsPadPrint
				,@IsAbnormal = IsAbnormal
				,@IsFirstTable = First_Table
			FROM #SPD_Order_Scheduling_idx
			WHERE isnull(CutMachine_No, '') = ''
				--AND Priority_Level = @Priority_Level_Min
				AND Plan_Date = @Plan_Date_Min
			ORDER BY isnull(Order_Status_Type, 99)
				,PLAN_DATE
				,[IsEnough_Material] DESC
				,CASE 
					WHEN isnull(Paper_Sample, '') <> ''
						AND isnull(Bar_Code, '') <> ''
						THEN 0
					ELSE 1
					END
				,[Priority_Level]
				--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
				,isnull(IS_Last_Cut, 0)

			IF isnull(@rid, '') = ''
				AND NOT EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx
					WHERE isnull(CutMachine_No, '') = ''
					)
			BEGIN
				PRINT '222222222222222222,@Plan_Date_Min=' + CONVERT(VARCHAR(30), @Plan_Date_Min, 21) + ',@Priority_Level_Min=' + CONVERT(VARCHAR(10), @Priority_Level_Min)

				BREAK;
			END

			--处理插单
			IF ISNULL(@Adjust_Machine_No, '') <> ''
			BEGIN
				SELECT @CutMachine_No_Adjust = CutMachine_NO
				FROM #TB_SpreadMachine
				WHERE SpreadMachine_No = @Adjust_Machine_No
					AND isnull(Valid_Status, 0) = 1
			END

			IF ISNULL(@CutMachine_NO, '') = ''
			BEGIN
				IF object_id('tempdb..#cut_date_Min') IS NOT NULL
					DROP TABLE #cut_date_Min

				SELECT CutMachine_No
					,cut_date_Min = SUM(ISNULL(pull_date_Min, 0))
				INTO #cut_date_Min
				FROM #SPD_Order_Scheduling_idx
				WHERE ISNULL(CutMachine_No, '') <> ''
					AND ISNULL(Order_Status_Type, 0) > 0
				--AND Plan_Date = @Plan_Date_Min
				GROUP BY CutMachine_No

				--多少个拉布机平分
				UPDATE c
				SET c.cut_date_Min = c.cut_date_Min / s.Spread_Count
				FROM #cut_date_Min c
				INNER JOIN #TB_SpreadMachine_Count s ON c.CutMachine_No = s.CutMachine_No

				INSERT INTO #cut_date_Min (
					CutMachine_No
					,cut_date_Min
					)
				SELECT DISTINCT M.CutMachine_No
					,cut_date_Min = 0.00
				FROM #TB_SpreadMachine M WITH (NOLOCK)
				LEFT JOIN #cut_date_Min C ON M.CutMachine_No = C.CutMachine_No
				WHERE C.CutMachine_No IS NULL
					AND ISNULL(M.Valid_Status, 0) = 1

				--SELECT @print_Msg = (
				--		SELECT *
				--		FROM #cut_date_Min
				--		FOR JSON PATH
				--		)
				--PRINT '333333333333:' + @print_Msg
				DELETE
				FROM #cut_date_Min
				WHERE CutMachine_No NOT IN (
						SELECT CutMachine_No
						FROM #TB_SpreadMachine M WITH (NOLOCK)
						WHERE ISNULL(M.Valid_Status, 0) = 1
						)

				SELECT TOP 1 @CutMachine_No = C.CutMachine_No
				FROM #cut_date_Min C
				INNER JOIN #TB_SpreadMachine S ON C.CutMachine_No = S.CutMachine_No
				INNER JOIN #Pre_Same_MO_Batch B ON B.CutMachine_No = S.CutMachine_No
					AND B.Batch_No = @Batch_No
					AND B.MO_NO = @MO_NO
				WHERE ISNULL(Marker_Width, 1000) >= ISNULL(@Marker_Width, 0)
					AND 1 = CASE 
						WHEN ISNULL(@Is_Small_Order, 0) = ISNULL(S.Is_Small_Order, 0)
							OR ISNULL(@Is_Small_Order, 0) = 0
							THEN 1
						ELSE 0
						END
					AND 1 = CASE 
						WHEN ISNULL(@IsPadPrint, 0) = ISNULL(S.IsPadPrint, 0)
							OR ISNULL(@IsPadPrint, 0) = 0
							THEN 1
						ELSE 0
						END
					AND ISNULL(S.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
					AND ISNULL(S.IsFirstTable, 0) = ISNULL(@IsFirstTable, 0)
				ORDER BY cut_date_Min

				IF ISNULL(@CutMachine_No, '') = ''
				BEGIN
					SELECT TOP 1 @CutMachine_No = C.CutMachine_No
					FROM #cut_date_Min C
					INNER JOIN #TB_SpreadMachine S ON C.CutMachine_No = S.CutMachine_No
					--INNER JOIN #Pre_Same_MO_Batch B ON B.CutMachine_No = S.CutMachine_No
					--	AND B.Batch_No = @Batch_No
					--	AND B.So_No = @SO_No
					WHERE ISNULL(Marker_Width, 1000) >= ISNULL(@Marker_Width, 0)
						AND 1 = CASE 
							WHEN ISNULL(@Is_Small_Order, 0) = ISNULL(S.Is_Small_Order, 0)
								OR ISNULL(@Is_Small_Order, 0) = 0
								THEN 1
							ELSE 0
							END --S.Is_Small_Order >= @Is_Small_Order
						AND 1 = CASE 
							WHEN ISNULL(@IsPadPrint, 0) = ISNULL(S.IsPadPrint, 0)
								OR ISNULL(@IsPadPrint, 0) = 0
								THEN 1
							ELSE 0
							END
						AND ISNULL(S.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
						AND ISNULL(S.IsFirstTable, 0) = ISNULL(@IsFirstTable, 0)
					ORDER BY cut_date_Min
				END
			END

			IF ISNULL(@CutMachine_No, '') = ''
			BEGIN
				SELECT TOP 1 @CutMachine_No = CutMachine_No
				FROM #TB_SpreadMachine S
				WHERE isnull(Valid_Status, 0) = 1
					AND isnull(Marker_Width, 0) >= isnull(@Marker_Width, 0)
					AND 1 = CASE 
						WHEN ISNULL(@Is_Small_Order, 0) = ISNULL(Is_Small_Order, 0)
							OR ISNULL(@Is_Small_Order, 0) = 0
							THEN 1
						ELSE 0
						END
					AND 1 = CASE 
						WHEN ISNULL(@IsPadPrint, 0) = ISNULL(S.IsPadPrint, 0)
							OR ISNULL(@IsPadPrint, 0) = 0
							THEN 1
						ELSE 0
						END
					AND ISNULL(S.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
					AND ISNULL(S.IsFirstTable, 0) = ISNULL(@IsFirstTable, 0)
			END

			IF ISNULL(@CutMachine_No, '') = ''
			BEGIN
				--SELECT TOP 1 @CutMachine_No = CutMachine_No
				--FROM #TB_SpreadMachine
				--WHERE isnull(Valid_Status, 0) = 1
				SELECT TOP 1 @CutMachine_No = 'TBD'
			END

			SELECT @Cut_SeqNO = ISNULL(MAX(isnull(Cut_SeqNO, 0)), 0)
			FROM #SPD_Order_Scheduling_idx
			WHERE CutMachine_No = @CutMachine_No

			SELECT @Cut_SeqNO = @Cut_SeqNO + 1

			UPDATE #SPD_Order_Scheduling_idx
			SET CutMachine_No = @CutMachine_No
				,Cut_SeqNO = @Cut_SeqNO
				,SpreadMachine_No = CASE 
					WHEN @CutMachine_No = 'TBD'
						THEN 'TBD'
					ELSE ''
					END
			WHERE RID = @RID

			--IF object_id('tempdb..#Same_MO_Batch_RID') IS NOT NULL
			--	DROP TABLE #Same_MO_Batch_RID
			--SELECT RID
			--	,Cut_SeqNO = @Cut_SeqNO + ROW_NUMBER() OVER (
			--		ORDER BY isnull(Order_Status_Type, 99)
			--			,PLAN_DATE
			--			,[IsEnough_Material] DESC
			--			,CASE 
			--				WHEN isnull(Paper_Sample, '') <> ''
			--					THEN 0
			--				ELSE 1
			--				END
			--			,[Priority_Level]
			--			,isnull(IS_Last_Cut, 0)
			--		)
			--INTO #Same_MO_Batch_RID
			--FROM #SPD_Order_Scheduling_idx
			--WHERE isnull(CutMachine_No, '') = ''
			--	--AND Priority_Level = @Priority_Level_Min
			--	AND Plan_Date = @Plan_Date_Min
			--	AND MO_NO = @MO_NO
			--	AND Batch_no = @Batch_No
			--UPDATE D
			--SET D.CutMachine_No = @CutMachine_No
			--	,D.Cut_SeqNO = C.Cut_SeqNO
			--FROM #SPD_Order_Scheduling_idx D
			--INNER JOIN #Same_MO_Batch_RID C ON C.RID = D.RID
			--SELECT @JsonStr = ''
			--SELECT @JsonStr = (
			--		SELECT TOP 1 d.*
			--		FROM #SPD_Order_Scheduling_idx D
			--		INNER JOIN #Same_MO_Batch_RID C ON C.RID = D.RID
			--		FOR JSON PATH
			--		)
			--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
			--	,@Action_ID = 'Job'
			--	,@Action_Type = 'Same_MO_Batch_RID'
			--	,@Action_Message = N'相同SO缸号排在同一个裁剪机'
			--SELECT @JsonStr = ''
			--SELECT @JsonStr = (
			--		SELECT TOP 1 *
			--		FROM #SPD_Order_Scheduling_idx
			--		WHERE RID = @RID
			--		FOR JSON PATH
			--		)
			--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
			--	,@Action_ID = 'Job'
			--	,@Action_Type = 'AllocatedCut'
			--	,@Action_Message = N'初步分配裁剪机'
			SELECT @Action_ID = 'Job'
				,@Action_Type = 'AllocatedCut'
				,@Action_Message = N'初步分配裁剪机'

			INSERT INTO #SPD_Order_Scheduling_log (
				RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID
				,Action_Type
				,Action_Date
				,Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
				)
			SELECT RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID = @Action_ID
				,Action_Type = @Action_Type
				,Action_Date = GETDATE()
				,Action_Message = @Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No = SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
			FROM #SPD_Order_Scheduling_idx
			WHERE RID = @RID
		END

		DECLARE @MAX_pull_Mins DECIMAL(18, 4) = 0
			,@MIN_pull_Mins DECIMAL(18, 4) = 0

		--SELECT *
		--FROM #SPD_Order_Scheduling_idx
		IF object_id('tempdb..#CutMachine_No_idx') IS NOT NULL
			DROP TABLE #CutMachine_No_idx

		SELECT idx = ROW_NUMBER() OVER (
				ORDER BY CutMachine_No
				)
			,CutMachine_No
		INTO #CutMachine_No_idx
		FROM (
			SELECT DISTINCT CutMachine_No
			FROM #SPD_Order_Scheduling_idx
			) D

		IF object_id('tempdb..#SpreadMachine_No_idx') IS NOT NULL
			DROP TABLE #SpreadMachine_No_idx

		SELECT idx = ROW_NUMBER() OVER (
				ORDER BY SpreadMachine_No
				)
			,SpreadMachine_No
		INTO #SpreadMachine_No_idx
		FROM (
			SELECT DISTINCT SpreadMachine_No
			FROM #TB_SpreadMachine --WITH (NOLOCK)
			WHERE ISNULL(Valid_Status, 0) = 1
			) D

		SELECT @index = 1

		DECLARE @SpreadSeqNO INT = 0
			,@SpreadMachine_No VARCHAR(100) = ''
			,@SpreadMachine_No_Adjust VARCHAR(100) = ''
			,@SpreadMachine_No_SO_Batch VARCHAR(100) = ''
			,@SpreadMachine_No_Rob VARCHAR(100) = ''
			,@SpreadMachine_idx INT = 0
		DECLARE @CutMachine_No_Current VARCHAR(50) = ''
			,@Spread_Plan_Date DATE = NULL

		UPDATE #SPD_Order_Scheduling_idx
		SET Cut_SeqNO = NULL
		WHERE SeqNO IS NULL

		--SELECT @JsonStr = ''
		--SELECT @JsonStr = (
		--		SELECT *
		--		FROM #SPD_Order_Scheduling_idx
		--		FOR JSON PATH
		--		)
		----DECLARE @Cut_Action_Message NVARCHAR(MAX) = N'计算物料前'
		--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
		--	,@Action_ID = 'Job'
		--	,@Action_Type = 'BeforeAllocatedSpread'
		--	,@Action_Message = N'分配拉布机前'
		SELECT @Action_ID = 'Job'
			,@Action_Type = 'BeforeAllocatedSpread'
			,@Action_Message = N'分配拉布机前'

		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = @Action_ID
			,Action_Type = @Action_Type
			,Action_Date = GETDATE()
			,Action_Message = @Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM #SPD_Order_Scheduling_idx

		--WHERE RID = @RID
		DECLARE @Spread_Scan_Time DATETIME = NULL
			,@Plan_Pull_Date_Start DATETIME = NULL
			,@Plan_Pull_Date_Start_Last DATETIME = NULL
			,@Plan_Pull_Date_End DATETIME = NULL
			,@Plan_Cut_Date_Start DATETIME = NULL
			,@Plan_Cut_Date_End DATETIME = NULL
			,@pull_date_Min DECIMAL(18, 2) = NULL
			,@Cut_date_Min DECIMAL(18, 2) = NULL
			,@SeqNO INT = 1
		DECLARE @IS_Last_Cut BIT = 0
			,@IS_Merge_Cut BIT = 0
			,@Assigned_SpreadMachine_No VARCHAR(50) = ''
		DECLARE @Plan_Pull_Date_Start_idx DATETIME = NULL
			,@SpreadMachine_No_idx VARCHAR(50) = ''
			,@index24 INT = 0
			,@RID_24 VARCHAR(50) = ''
			,@Adjust_Time DATETIME = NULL
		DECLARE @Plan_Pull_Date_Start_idx26 DATETIME = NULL
			,@SpreadMachine_No_idx26 VARCHAR(50) = ''
			,@index26 INT = 0
			,@RID_26 VARCHAR(50) = ''
			,@index27 INT = 0
			,@RID_27 VARCHAR(50) = ''
		--后拉检查
		DECLARE @index25 INT = 1
			,@RID_25 VARCHAR(50) = ''
			,@CurrentDate DATETIME = NULL
			,@Table_No INT = 0
			,@Spd_Type VARCHAR(50) = ''
		DECLARE @Batch_List TABLE (Batch_No NVARCHAR(400))

		--把已拉完的床次先计算裁剪时间 Damon gu 2025-04-10
		--SELECT *
		--FROM #SPD_Order_Scheduling_idx
		--WHERE Order_Status_Type = 0
		--	AND ISNULL(IS_CUT, 0) = 0
		SELECT @Quit_Index = 1

		--计算已拉未裁时间
		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_idx
				WHERE --ISNULL(SpreadMachine_No, '') = ''
					Plan_Cut_Date_End IS NULL
					AND Order_Status_Type = 0
					AND ISNULL(IS_CUT, 0) = 0
				)
			AND @Quit_Index <= 20000
		BEGIN
			PRINT N'计算已拉未裁时间'

			SELECT @Quit_Index = @Quit_Index + 1

			SELECT @RID = ''
				,@CutMachine_No = ''
				,@SpreadMachine_No = ''
				,@SO_No = ''
				,@MO_No = ''
				,@Batch_No = ''
				,@Spread_Scan_Time = NULL
				,@Cut_SeqNO = 1
				,@SeqNO = 1
				,@Plan_Pull_Date_End = NULL
				,@Plan_Pull_Date_Start = NULL
				,@pull_date_Min = 0
				,@IS_Last_Cut = 0
				,@Plan_Pull_Date_Start_Last = NULL
				,@Action_Message = ''

			SELECT TOP 1 @RID = RID
				,@CutMachine_No = CutMachine_No
				,@SpreadMachine_No = SpreadMachine_No
				,@SO_No = SO_No
				,@MO_No = MO_No
				,@Batch_No = Batch_No
				,@Spread_Scan_Time = Spread_Scan_Time
				,@Cut_SeqNO = Cut_SeqNO
				,@SeqNO = SeqNO
				,@pull_date_Min = cut_date_Min
				--CASE 
				--	WHEN ISNULL(cut_date_Min, 10.00) <= 0
				--		THEN 10.0
				--	ELSE ISNULL(cut_date_Min, 10.00)
				--	END
				,@IS_Last_Cut = IS_Last_Cut
				,@Plan_Pull_Date_End = Plan_Pull_Date_End
			FROM #SPD_Order_Scheduling_idx
			WHERE --ISNULL(SpreadMachine_No, '') = ''
				Plan_Cut_Date_End IS NULL
				AND Order_Status_Type = 0
				AND ISNULL(IS_CUT, 0) = 0
			ORDER BY Plan_Pull_Date_End DESC

			IF @pull_date_Min = 0
			BEGIN
				SELECT TOP 1 @pull_date_Min = Cut_Date
				FROM SPD_Order_Cut_Plan_Date_ALL_Lot_log WITH (NOLOCK)
				WHERE RID = @RID
					AND Cut_Date > 0
					AND Action_Date >= DATEADD(DAY, - 2, GETDATE())
				ORDER BY Action_Date DESC
			END

			SELECT @Action_Message = N'分配拉布机前计算裁剪时间,@pull_date_Min=' + CONVERT(VARCHAR(20), @pull_date_Min)

			SELECT @Plan_Cut_Date_Start = NULL

			SELECT TOP 1 @Plan_Cut_Date_Start = Plan_Cut_Date_End --ISNULL(MAX(Plan_Cut_Date_End), GETDATE())
			FROM #SPD_Order_Scheduling_idx
			WHERE CutMachine_No = @CutMachine_No
				AND Plan_Cut_Date_End IS NOT NULL
			ORDER BY Plan_Cut_Date_End DESC

			SELECT @Action_Message = @Action_Message + ',1:@Plan_Cut_Date_Start=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Cut_Date_Start, 21), '')

			IF @Plan_Cut_Date_Start IS NULL
				OR @Plan_Cut_Date_Start < @Plan_Pull_Date_End --还没分配或开始时间早于拉布结束时间，取当前拉布结束时间
			BEGIN
				SELECT @Plan_Cut_Date_Start = @Plan_Pull_Date_End
			END

			SELECT @Action_Message = @Action_Message + ',2:@Plan_Cut_Date_Start=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Cut_Date_Start, 21), '')

			SELECT @Plan_Cut_Date_Start = ISNULL(@Plan_Cut_Date_Start, GETDATE())

			SELECT @Action_Message = @Action_Message + ',3:@Plan_Cut_Date_Start=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Cut_Date_Start, 21), '')

			SELECT @Plan_Cut_Date_End = [dbo].[fn_CCT_GetEndTimeNew](dateadd(SECOND, @pull_date_Min * 60.00, ISNULL(@Plan_Cut_Date_Start, GETDATE())),@pull_date_Min)

			SELECT @Action_Message = @Action_Message + ',4:@Plan_Cut_Date_End=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Cut_Date_End, 21), '')

			IF @Plan_Cut_Date_End <= GETDATE()
			BEGIN
				SELECT @Plan_Cut_Date_End = [dbo].[fn_CCT_GetEndTimeNew](GETDATE(),@pull_date_Min)
			END

			SELECT @Action_Message = @Action_Message + ',5:@Plan_Cut_Date_End=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Cut_Date_End, 21), '')

			UPDATE t
			SET Plan_Cut_Date_Start = ISNULL(@Plan_Cut_Date_Start, GETDATE())
				,Plan_Cut_Date_End = @Plan_Cut_Date_End
				,Act_Cut_Date_Start = ISNULL(@Plan_Cut_Date_Start, GETDATE())
				,Act_Cut_Date_End = @Plan_Cut_Date_End
			FROM #SPD_Order_Scheduling_idx t
			WHERE RID = @RID

			--SELECT @JsonStr = ''
			--SELECT @JsonStr = (
			--		SELECT TOP 1 *
			--		FROM #SPD_Order_Scheduling_idx
			--		WHERE RID = @RID
			--		FOR JSON PATH
			--		)
			--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
			--	,@Action_ID = 'JobSeq'
			--	,@Action_Type = 'CutTimeBeforeSPDTime_End'
			--	,@Action_Message = @Action_Message -- N'分配拉布机前计算裁剪时间'
			SELECT @Action_ID = 'Job'
				,@Action_Type = 'CutTimeBeforeSPDTime_End'

			--,@Action_Message =  @Action_Message
			INSERT INTO #SPD_Order_Scheduling_log (
				RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID
				,Action_Type
				,Action_Date
				,Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
				)
			SELECT RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID = @Action_ID
				,Action_Type = @Action_Type
				,Action_Date = GETDATE()
				,Action_Message = @Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No = SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
			FROM #SPD_Order_Scheduling_idx
			WHERE RID = @RID
		END

		--SELECT #TB_SpreadMachine = ''
		--	,*
		--FROM #TB_SpreadMachine
		IF object_id('tempdb..#SPD_Order_Scheduling_MergeCut_Split') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_MergeCut_Split

		SELECT MergeCut_Split_index = ROW_NUMBER() OVER (
				ORDER BY table_no
				)
			,*
		INTO #SPD_Order_Scheduling_MergeCut_Split
		FROM #SPD_Order_Scheduling_idx S
		WHERE ISNULL(IS_Merge_Cut, 0) = 1
			AND ISNULL(Merge_Cut_Remark, '') <> ''

		SELECT @index = 1

		DELETE
		FROM SPD_Merge_Table_Info
		WHERE Data_Type = 'MergeCut'

		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_MergeCut_Split
				WHERE MergeCut_Split_index >= @index
				)
		BEGIN
			SELECT @RID = ''
				,@Merge_Cut_Remark = ''

			SELECT @RID = RID
				,@Merge_Cut_Remark = Merge_Cut_Remark
			FROM #SPD_Order_Scheduling_MergeCut_Split
			WHERE MergeCut_Split_index = @index

			DELETE
			FROM @Merge_Table

			INSERT INTO @Merge_Table (Table_No)
			SELECT VALUE
			FROM STRING_SPLIT(@Merge_Cut_Remark, '/')

			--UPDATE S
			--SET S.Merge_Cut_RID = @RID
			INSERT INTO SPD_Merge_Table_Info (
				RID
				,Mst_RID
				,Dtl_RID
				,Lot_number_Cur
				,Create_date
				,Create_ID
				,Data_Type
				)
			SELECT RID = convert(VARCHAR(50), newid())
				,Mst_RID = @RID
				,Dtl_RID = RID
				,Lot_number_Cur = @Calculate_LotNumber
				,Create_date = GETDATE()
				,Create_ID = '1'
				,Data_Type = 'MergeCut'
			FROM #SPD_Order_Scheduling_idx S
			INNER JOIN @Merge_Table M ON CONVERT(VARCHAR(20), S.TABLE_NO) = M.TABLE_NO
			WHERE MO_NO = @MO_NO --2025-03-31 已和tony&cassie确认，合拉BY MO
				AND RID <> @RID

			--ALTER TABLE SPD_Merge_Table_Info ADD Create_ID VARCHAR(20) NULL
			--UPDATE S
			--SET S.Merge_Cut_RID = @RID
			INSERT INTO SPD_Merge_Table_Info (
				RID
				,Mst_RID
				,Dtl_RID
				,Lot_number_Cur
				,Create_date
				,Create_ID
				,Data_Type
				)
			SELECT RID = convert(VARCHAR(50), newid())
				,Mst_RID = @RID
				,Dtl_RID = RID
				,Lot_number_Cur = @Calculate_LotNumber
				,Create_date = GETDATE()
				,Create_ID = '2'
				,Data_Type = 'MergeCut'
			FROM #SPD_Order_Scheduling_idx S
			WHERE SO_NO = @SO_NO
				AND Batch_No = @Batch_No
				--AND ISNULL(S.Merge_Cut_RID, '') = ''
				AND Ori_Plan_Date = @Ori_Plan_Date
				AND RID <> @RID

			--AND Ori_Plan_Date = @Ori_Plan_Date
			--UPDATE S
			--SET S.Merge_Cut_RID = @RID
			--FROM #SPD_Order_Scheduling_idx S
			--WHERE SO_NO = @SO_NO
			--	AND Batch_No = @Batch_No
			--	--AND ISNULL(S.Merge_Cut_RID, '') = ''
			--	AND Ori_Plan_Date = @Ori_Plan_Date
			SELECT @index = @index + 1
		END

		IF object_id('tempdb..#SPD_Order_Scheduling_LastCut_Split') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_LastCut_Split

		SELECT MergeCut_Split_index = ROW_NUMBER() OVER (
				ORDER BY table_no
				)
			,*
		INTO #SPD_Order_Scheduling_LastCut_Split
		FROM #SPD_Order_Scheduling_idx S
		WHERE ISNULL(IS_Last_Cut, 0) = 1

		--AND ISNULL(Merge_Cut_Remark, '') <> ''
		SELECT @index = 1

		DELETE
		FROM SPD_Merge_Table_Info
		WHERE Data_Type = 'LastCut'

		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_LastCut_Split
				WHERE MergeCut_Split_index >= @index
				)
		BEGIN
			SELECT @RID = ''
				,@SO_NO = ''
				,@Batch_No = ''
				,@Ori_Plan_Date = ''

			SELECT @RID = RID
				,@SO_NO = SO_NO
				,@Batch_No = Batch_No
				,@Ori_Plan_Date = Ori_Plan_Date
			FROM #SPD_Order_Scheduling_LastCut_Split
			WHERE MergeCut_Split_index = @index

			--UPDATE S
			--SET S.Merge_Cut_RID = @RID
			INSERT INTO SPD_Merge_Table_Info (
				RID
				,Mst_RID
				,Dtl_RID
				,Lot_number_Cur
				,Create_date
				,Create_ID
				,Data_Type
				)
			SELECT RID = convert(VARCHAR(50), newid())
				,Mst_RID = @RID
				,Dtl_RID = RID
				,Lot_number_Cur = @Calculate_LotNumber
				,Create_date = GETDATE()
				,Create_ID = '1'
				,Data_Type = 'LastCut'
			FROM #SPD_Order_Scheduling_idx S
			--INNER JOIN @Merge_Table M ON CONVERT(VARCHAR(20), S.TABLE_NO) = M.TABLE_NO
			WHERE Batch_No = @Batch_No
				AND SO_NO = @SO_NO
				AND ISNULL(IS_Last_Cut, 0) = 0
				AND RID <> @RID
				AND Order_Status_Type >= 1
				AND Ori_Plan_Date = @Ori_Plan_Date

			--SELECT @JsonStr = ''
			--SELECT @JsonStr = (
			--		SELECT S.*
			--		FROM #SPD_Order_Scheduling_idx S
			--		WHERE S.RID = @RID
			--		FOR JSON PATH
			--		)
			--SELECT @Action_Message = N'生成后来关系'
			--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
			--	,@Action_ID = 'JobSeq'
			--	,@Action_Type = 'CreateLastCutInfo'
			--	,@Action_Message = @Action_Message
			SELECT @Action_ID = 'Job'
				,@Action_Type = 'CreateLastCutInfo'
				,@Action_Message = N'生成后来关系'

			INSERT INTO #SPD_Order_Scheduling_log (
				RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID
				,Action_Type
				,Action_Date
				,Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
				)
			SELECT RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID = @Action_ID
				,Action_Type = @Action_Type
				,Action_Date = GETDATE()
				,Action_Message = @Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No = SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
			FROM #SPD_Order_Scheduling_idx
			WHERE RID = @RID

			SELECT @index = @index + 1
		END

		IF object_id('tempdb..#SPD_Order_Scheduling_MergeBatch_Split') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_MergeBatch_Split

		SELECT MergeBatch_Split_index = ROW_NUMBER() OVER (
				ORDER BY table_no
				)
			,*
		INTO #SPD_Order_Scheduling_MergeBatch_Split
		FROM #SPD_Order_Scheduling_idx S
		WHERE Batch_No LIKE '%;%'

		--AND ISNULL(Merge_Cut_Remark, '') <> ''
		SELECT @index = 1

		DELETE
		FROM SPD_Merge_Table_Info
		WHERE Data_Type = 'MergeBatch'

		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_MergeBatch_Split
				WHERE MergeBatch_Split_index >= @index
				)
		BEGIN
			SELECT @RID = ''
				,@SO_NO = ''
				,@Batch_No = ''
				,@Ori_Plan_Date = ''

			SELECT @RID = RID
				,@SO_NO = SO_NO
				,@Batch_No = Batch_No
				,@Ori_Plan_Date = Ori_Plan_Date
			FROM #SPD_Order_Scheduling_MergeBatch_Split
			WHERE MergeBatch_Split_index = @index

			--UPDATE S
			--SET S.Merge_Cut_RID = @RID
			INSERT INTO SPD_Merge_Table_Info (
				RID
				,Mst_RID
				,Dtl_RID
				,Lot_number_Cur
				,Create_date
				,Create_ID
				,Data_Type
				)
			SELECT RID = convert(VARCHAR(50), newid())
				,Mst_RID = @RID
				,Dtl_RID = RID
				,Lot_number_Cur = @Calculate_LotNumber
				,Create_date = GETDATE()
				,Create_ID = '3'
				,Data_Type = 'MergeBatch'
			FROM #SPD_Order_Scheduling_idx S
			--INNER JOIN @Merge_Table M ON CONVERT(VARCHAR(20), S.TABLE_NO) = M.TABLE_NO
			WHERE --Batch_No = @Batch_No
				1 = dbo.fn_CCT_CheckBatchNoIsContain(@Batch_No, Batch_No)
				AND SO_NO = @SO_NO
				--AND ISNULL(IS_Last_Cut, 0) = 0
				AND RID <> @RID
				--AND Order_Status_Type >= 1
				AND Ori_Plan_Date = @Ori_Plan_Date

			SELECT @index = @index + 1
		END

		DECLARE @LineBalance_SpreadMachine_PutTableQty INT = 2
			,@Current_PutTableQty INT = 0

		SELECT @LineBalance_SpreadMachine_PutTableQty = SYS_VALUE
		FROM system_table WITH (NOLOCK)
		WHERE SYS_CODE = 'LineBalance_SpreadMachine_PutTableQty'

		SELECT @Quit_Index = 1

		DECLARE @PutTableQty_Quit_Index INT = 0
		DECLARE @LastCut_SpreadMachine_No VARCHAR(50) = ''
			,@LastCut_CutMachine_No VARCHAR(50) = ''
			,@IsFirst BIT = 0
		DECLARE @Quit_Index2 INT = 1
			,@Ori_SPD_RID VARCHAR(50) = ''
			,@PadPrint_RID VARCHAR(50) = ''
			,@Group_RID VARCHAR(50) = ''
			,@SPD_Limit_Layers INT = 120
			,@Plan_Layer_Qty INT = 0

		--Damon gu 2025-09-25 限制拉布层数
		SELECT @SPD_Limit_Layers = CONVERT(INT, SYS_VALUE)
		FROM System_Table WITH (NOLOCK)
		WHERE SYS_CODE = 'SPD_Limit_Layers'

		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = 'BreakMessage6'
			,Action_Type = 'BreakMessage6'
			,Action_Date = GETDATE()
			,Action_Message = 'BreakMessage6'
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = NULL
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
		FROM #SPD_Order_Scheduling_idx

		--分配拉布机
		WHILE EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_idx
				WHERE --ISNULL(SpreadMachine_No, '') = ''
					Plan_Pull_Date_Start IS NULL
					AND ISNULL(CutMachine_No, '') <> ''
				)
			AND @Quit_Index <= 20000
		BEGIN
			PRINT N'分配拉布机'

			SELECT @Quit_Index = @Quit_Index + 1

			PRINT '@index=' + CONVERT(VARCHAR(10), @Quit_Index)

			SELECT @CutMachine_No = ''
				,@SpreadMachine_No = ''
				,@Marker_Width = 0
				,@Is_Small_Order = 0
				,@IS_Last_Cut = 0
				,@IS_Merge_Cut = 0
				,@Table_No = 0
				,@IsFirst = 1
				,@IsStripe = 0
				,@IsPadPrint = 0
				,@IsAbnormal = 0
				,@IsFirstTable = 0

			IF object_id('tempdb..#pull_date_Min') IS NOT NULL
				DROP TABLE #pull_date_Min

			--PRINT '2157:@CutMachine_No=' + isnull(@CutMachine_No, 0)
			SELECT SpreadMachine_No = ISNULL(SpreadMachine_No, '')
				,pull_date_Min = SUM(isnull(pull_date_Min, 0))
			INTO #pull_date_Min
			FROM #SPD_Order_Scheduling_idx
			WHERE ISNULL(SpreadMachine_No, '') <> ''
				AND ISNULL(Order_Status_Type, 0) > 0
			--AND Plan_Pull_Date_Start IS NOT NULL
			GROUP BY ISNULL(SpreadMachine_No, '')

			INSERT INTO #pull_date_Min (
				SpreadMachine_No
				,pull_date_Min
				)
			SELECT DISTINCT M.SpreadMachine_No
				,pull_date_Min = 0
			FROM #TB_SpreadMachine M WITH (NOLOCK)
			LEFT JOIN #pull_date_Min C ON M.SpreadMachine_No = C.SpreadMachine_No
			--AND ISNULL(M.Valid_Status, 0) = 1
			WHERE C.SpreadMachine_No IS NULL
				--AND isnull(M.CutMachine_No, '') = @CutMachine_No
				AND ISNULL(M.Valid_Status, 0) = 1

			DELETE
			FROM #pull_date_Min
			WHERE SpreadMachine_No NOT IN (
					SELECT SpreadMachine_No
					FROM #TB_SpreadMachine M -- WITH (NOLOCK)
					WHERE ISNULL(M.Valid_Status, 0) = 1
					)

			SELECT TOP 1 @SpreadMachine_No = P.SpreadMachine_No
				,@CutMachine_No = CutMachine_No
			FROM #pull_date_Min p
			INNER JOIN #TB_SpreadMachine S ON P.SpreadMachine_No = S.SpreadMachine_No
			ORDER BY pull_date_Min

			SELECT @CurrentDate = getdate()

			SELECT @Marker_Width = Marker_Width
				,@Is_Small_Order = Is_Small_Order
				,@IsStripe = S.IsStripe
				,@IsPadPrint = S.IsPadPrint
				,@IsAbnormal = S.IsAbnormal
				,@IsFirstTable = S.IsFirstTable
			FROM #TB_SpreadMachine S
			WHERE SpreadMachine_No = @SpreadMachine_No

			--判断是否首床
			SELECT TOP 1 @IsFirst = 0
			FROM #SPD_Order_Scheduling_idx S
			WHERE S.SpreadMachine_No = @SpreadMachine_No
				AND Order_Status_Type >= 1
				AND Plan_Pull_Date_Start IS NULL

			IF object_id('tempdb..#Plan_Pull_Date_Min') IS NOT NULL
				DROP TABLE #Plan_Pull_Date_Min

			SELECT TOP 0 plan_date = @Work_Date
				,pull_date_min = convert(DECIMAL(18, 4), 0) --DATEDIFF(SECOND, Plan_Pull_Date_End, Plan_Cut_Date_End) / 60.00
			INTO #Plan_Pull_Date_Min

			IF @IsFirst = 0
			BEGIN
				IF object_id('tempdb..#Plan_Cut_Date_End_Max') IS NOT NULL
					DROP TABLE #Plan_Cut_Date_End_Max

				SELECT plan_date
					,Plan_Cut_Date_End = MAX(Plan_Cut_Date_End)
				INTO #Plan_Cut_Date_End_Max
				FROM #SPD_Order_Scheduling_idx S
				WHERE CutMachine_No = @CutMachine_No
					AND Plan_Cut_Date_End IS NOT NULL
				GROUP BY plan_date

				IF NOT EXISTS (
						SELECT TOP 1 1
						FROM #Plan_Cut_Date_End_Max
						)
				BEGIN
					INSERT INTO #Plan_Cut_Date_End_Max (
						plan_date
						,Plan_Cut_Date_End
						)
					SELECT plan_date = @Work_Date
						,Plan_Cut_Date_End = getdate()
				END

				IF object_id('tempdb..#Plan_Pull_Date_End_Max') IS NOT NULL
					DROP TABLE #Plan_Pull_Date_End_Max

				SELECT plan_date
					,Plan_Pull_Date_End = MAX(Plan_Pull_Date_End)
				INTO #Plan_Pull_Date_End_Max
				FROM #SPD_Order_Scheduling_idx S
				WHERE CutMachine_No = @CutMachine_No
					AND Plan_Pull_Date_End IS NOT NULL
				GROUP BY plan_date

				IF NOT EXISTS (
						SELECT TOP 1 1
						FROM #Plan_Pull_Date_End_Max
						)
				BEGIN
					INSERT INTO #Plan_Pull_Date_End_Max (
						plan_date
						,Plan_Pull_Date_End
						)
					SELECT plan_date = @Work_Date
						,Plan_Pull_Date_End = getdate()
				END

				--SELECT #Plan_Pull_Date_End_Max = ''
				--	,*
				--FROM #Plan_Pull_Date_End_Max
				--SELECT #Plan_Cut_Date_End_Max = ''
				--	,*
				--FROM #Plan_Cut_Date_End_Max
				INSERT INTO #Plan_Pull_Date_Min (
					plan_date
					,pull_date_min
					)
				SELECT P.plan_date
					,pull_date_min = DATEDIFF(SECOND, Plan_Pull_Date_End, Plan_Cut_Date_End) / 60.00
				--INTO #Plan_Pull_Date_Min
				FROM #Plan_Pull_Date_End_Max p
				LEFT JOIN #Plan_Cut_Date_End_Max C ON P.plan_date = C.plan_date
					--SELECT @Current_PutTableQty = 0
					--SELECT @Current_PutTableQty = COUNT(1)
					--FROM #SPD_Order_Scheduling_idx
					--WHERE SpreadMachine_No = @SpreadMachine_No
					--	AND ISNULL(IS_CUT, 0) = 0
					--	AND Plan_Cut_Date_End >= @Plan_Pull_Date_Start
					--SELECT @PutTableQty_Quit_Index = 1
					--直到只有两床
					--WHILE @Current_PutTableQty >= @LineBalance_SpreadMachine_PutTableQty
					--SELECT #Plan_Pull_Date_Min = ''
					--	,*
					--FROM #Plan_Pull_Date_Min
			END

			--BEGIN
			SELECT @RID = ''
				,@SpreadMachine_No_Adjust = ''
				,@SpreadMachine_No_SO_Batch = ''
				,@SpreadSeqNO = 0
				,@print_Msg = ''
				,@Adjust_Machine_No = ''
				,@SO_No = ''
				,@Batch_No = ''
				,@CutMachine_No_Current = ''
				,@Spread_Plan_Date = NULL
				,@SpreadMachine_idx = 0
				,@IS_Last_Cut = 0
				,@IS_Merge_Cut = 0
				,@Ori_Plan_Date = NULL
				,@MO_NO = ''
				,@Merge_Cut_Remark = ''
				,@Assigned_SpreadMachine_No = ''
				,@Table_No = 0
				,@Spd_Type = ''
				,@Order_Status_Type = 99
				,@Cut_date_Min = 0
				,@Ori_SPD_RID = ''

			SELECT TOP 1 @RID = RID
				,@Adjust_Machine_No = Adjust_Machine_No
				,@SO_No = SO_No
				,@Batch_No = Batch_No
				,@Spread_Plan_Date = Plan_Date
				--,@Marker_Width = ISNULL(Marker_Width, 0)
				--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
				,@CutMachine_No = CutMachine_No
				,@IS_Last_Cut = IS_Last_Cut
				,@IS_Merge_Cut = IS_Merge_Cut
				,@Ori_Plan_Date = Ori_Plan_Date
				,@MO_NO = MO_NO
				,@Merge_Cut_Remark = Merge_Cut_Remark
				,@Assigned_SpreadMachine_No = SpreadMachine_No
				,@Table_No = Table_No
				,@Spd_Type = Spd_Type
				,@Order_Status_Type = Order_Status_Type
				,@Cut_date_Min = cut_date_Min
			FROM #SPD_Order_Scheduling_idx S
			WHERE --ISNULL(SpreadMachine_No, '') = ''
				Plan_Pull_Date_Start IS NULL
				AND ISNULL(CutMachine_No, '') <> ''
				--AND ISNULL(CutMachine_No, '') IN (
				--	SELECT DISTINCT CutMachine_No = ISNULL(CutMachine_No, '')
				--	FROM #MES_CuttingMachineMap
				--	WHERE isnull(SpreadMachine_No, '') = @SpreadMachine_No
				--	UNION
				--	SELECT DISTINCT CutMachine_No
				--	FROM TB_SpreadMachine WITH (NOLOCK)
				--	WHERE Valid_Status = 1
				--		AND isnull(SpreadMachine_No, '') = @SpreadMachine_No
				--	)
				--AND ISNULL(S.Marker_Width, 0) <= ISNULL(@Marker_Width, 1000)
				--AND 1 = CASE 
				--	WHEN ISNULL(S.Is_Small_Order, 0) = ISNULL(@Is_Small_Order, 0)
				--		OR ISNULL(S.Is_Small_Order, 0) = 0
				--		THEN 1
				--	ELSE 0
				--	END
				AND ISNULL(SpreadMachine_No, '') <> ''
			ORDER BY ISNULL(S.Is_Now, 0) DESC
				--,CASE 
				--	WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
				--		THEN 0
				--	ELSE 1
				--	END
				,isnull(Order_Status_Type, 99)
				,CASE 
					WHEN isnull(Order_Status_Type, 99) = 2
						THEN S.SeqNO
					ELSE 999
					END
				,PLAN_DATE
				,[IsEnough_Material] DESC
				,CASE 
					WHEN isnull(Paper_Sample, '') <> ''
						THEN 0
					ELSE 1
					END
				,CASE 
					WHEN isnull(Bar_Code, '') <> ''
						THEN 0
					ELSE 1
					END
				,[Priority_Level]
				--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
				,ISNULL(IS_Last_Cut, 0)

			--,CASE 
			--	WHEN @IsFirst = 1 --当前床首床
			--		THEN S.pull_date_min --取最小
			--	ELSE (
			--			SELECT TOP 1 ABS(S.pull_date_min - DM.pull_date_min)
			--			FROM #Plan_Pull_Date_Min DM
			--			WHERE DM.PLAN_DATE = S.PLAN_DATE
			--			) --最接近优先
			--	END
			IF @RID <> ''
			BEGIN
				UPDATE S
				SET S.CaseNo = 1
				FROM #SPD_Order_Scheduling_idx S
				WHERE S.RID = @RID

				--SELECT @JsonStr = ''
				--SELECT @JsonStr = (
				--		SELECT S.*
				--		FROM #SPD_Order_Scheduling_idx S
				--		WHERE rid = @RID
				--		FOR JSON PATH
				--		)
				--SELECT @Action_Message = N'确定顺序位置'
				--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
				--	,@Action_ID = 'JobSeq'
				--	,@Action_Type = 'SetCaseNo'
				--	,@Action_Message = @Action_Message
				SELECT @Action_ID = 'JobSeq'
					,@Action_Type = 'SetCaseNo'

				--,@Action_Message = @Cut_Action_Message
				INSERT INTO #SPD_Order_Scheduling_log (
					RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID
					,Action_Type
					,Action_Date
					,Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
					)
				SELECT RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID = @Action_ID
					,Action_Type = @Action_Type
					,Action_Date = GETDATE()
					,Action_Message = @Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No = SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx
				WHERE RID = @RID
			END

			IF ISNULL(@RID, '') = ''
			BEGIN
				SELECT TOP 1 @RID = RID
					,@Adjust_Machine_No = Adjust_Machine_No
					,@SO_No = SO_No
					,@Batch_No = Batch_No
					,@Spread_Plan_Date = Plan_Date
					--,@Marker_Width = ISNULL(Marker_Width, 0)
					--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
					,@CutMachine_No = CutMachine_No
					,@IS_Last_Cut = IS_Last_Cut
					,@IS_Merge_Cut = IS_Merge_Cut
					,@Ori_Plan_Date = Ori_Plan_Date
					,@MO_NO = MO_NO
					,@Merge_Cut_Remark = Merge_Cut_Remark
					,@Assigned_SpreadMachine_No = SpreadMachine_No
					,@Table_No = Table_No
					,@Spd_Type = Spd_Type
					,@Order_Status_Type = Order_Status_Type
					,@Cut_date_Min = cut_date_Min
				FROM #SPD_Order_Scheduling_idx S
				WHERE --ISNULL(SpreadMachine_No, '') = ''
					Plan_Pull_Date_Start IS NULL
					AND ISNULL(CutMachine_No, '') <> ''
					AND ISNULL(CutMachine_No, '') IN (
						SELECT DISTINCT CutMachine_No = ISNULL(CutMachine_No, '')
						FROM #MES_CuttingMachineMap
						WHERE isnull(SpreadMachine_No, '') = @SpreadMachine_No
						
						UNION
						
						SELECT DISTINCT CutMachine_No
						FROM TB_SpreadMachine WITH (NOLOCK)
						WHERE Valid_Status = 1
							AND isnull(SpreadMachine_No, '') = @SpreadMachine_No
						)
					AND ISNULL(S.Marker_Width, 0) <= ISNULL(@Marker_Width, 1000)
					AND 1 = CASE 
						WHEN ISNULL(S.Is_Small_Order, 0) = ISNULL(@Is_Small_Order, 0)
							OR ISNULL(S.Is_Small_Order, 0) = 0
							THEN 1
						ELSE 0
						END
					AND 1 = CASE 
						WHEN ISNULL(S.IsPadPrint, 0) = ISNULL(@IsPadPrint, 0)
							OR ISNULL(S.IsPadPrint, 0) = 0
							THEN 1
						ELSE 0
						END
					AND ISNULL(S.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
					AND ISNULL(S.First_Table, 0) = ISNULL(@IsFirstTable, 0)
					AND ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
				ORDER BY ISNULL(S.Is_Now, 0) DESC
					,CASE 
						WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
							THEN 0
						ELSE 1
						END
					,isnull(Order_Status_Type, 99)
					,CASE 
						WHEN isnull(Order_Status_Type, 99) = 2
							THEN S.SeqNO
						ELSE 999
						END
					,PLAN_DATE
					,[IsEnough_Material] DESC
					,CASE 
						WHEN isnull(Paper_Sample, '') <> ''
							THEN 0
						ELSE 1
						END
					,CASE 
						WHEN isnull(Bar_Code, '') <> ''
							THEN 0
						ELSE 1
						END
					,[Priority_Level]
					--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
					,ISNULL(IS_Last_Cut, 0)
					,CASE 
						WHEN @IsFirst = 1 --当前床首床
							THEN S.pull_date_min --取最小
						ELSE (
								SELECT TOP 1 ABS(S.pull_date_min - DM.pull_date_min)
								FROM #Plan_Pull_Date_Min DM
								WHERE DM.PLAN_DATE = S.PLAN_DATE
								) --最接近优先
						END

				IF @RID <> ''
				BEGIN
					UPDATE S
					SET S.CaseNo = 2
					FROM #SPD_Order_Scheduling_idx S
					WHERE S.RID = @RID

					--SELECT @JsonStr = ''
					--SELECT @JsonStr = (
					--		SELECT S.*
					--		FROM #SPD_Order_Scheduling_idx S
					--		WHERE rid = @RID
					--		FOR JSON PATH
					--		)
					--SELECT @Action_Message = N'确定顺序位置'
					--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
					--	,@Action_ID = 'JobSeq'
					--	,@Action_Type = 'SetCaseNo'
					--	,@Action_Message = @Action_Message
					SELECT @Action_ID = 'JobSeq'
						,@Action_Type = 'SetCaseNo'
						,@Action_Message = N'确定顺序位置'

					INSERT INTO #SPD_Order_Scheduling_log (
						RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID
						,Action_Type
						,Action_Date
						,Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
						)
					SELECT RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID = @Action_ID
						,Action_Type = @Action_Type
						,Action_Date = GETDATE()
						,Action_Message = @Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No = SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
					FROM #SPD_Order_Scheduling_idx
					WHERE RID = @RID
				END
			END

			IF ISNULL(@RID, '') = ''
			BEGIN
				SELECT TOP 1 @RID = RID
					,@Adjust_Machine_No = Adjust_Machine_No
					,@SO_No = SO_No
					,@Batch_No = Batch_No
					,@Spread_Plan_Date = Plan_Date
					--,@Marker_Width = ISNULL(Marker_Width, 0)
					--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
					,@CutMachine_No = CutMachine_No
					,@IS_Last_Cut = IS_Last_Cut
					,@IS_Merge_Cut = IS_Merge_Cut
					,@Ori_Plan_Date = Ori_Plan_Date
					,@MO_NO = MO_NO
					,@Merge_Cut_Remark = Merge_Cut_Remark
					,@Assigned_SpreadMachine_No = SpreadMachine_No
					,@Table_No = Table_No
					,@Spd_Type = Spd_Type
					,@Order_Status_Type = Order_Status_Type
					,@Cut_date_Min = cut_date_Min
				FROM #SPD_Order_Scheduling_idx S
				WHERE --ISNULL(SpreadMachine_No, '') = ''
					Plan_Pull_Date_Start IS NULL
					AND ISNULL(CutMachine_No, '') <> ''
					AND ISNULL(CutMachine_No, '') IN (
						SELECT DISTINCT CutMachine_No = ISNULL(CutMachine_No, '')
						FROM #MES_CuttingMachineMap
						WHERE isnull(SpreadMachine_No, '') = @SpreadMachine_No
						
						UNION
						
						SELECT DISTINCT CutMachine_No
						FROM TB_SpreadMachine WITH (NOLOCK)
						WHERE Valid_Status = 1
							AND isnull(SpreadMachine_No, '') = @SpreadMachine_No
						)
					AND ISNULL(S.Marker_Width, 0) <= ISNULL(@Marker_Width, 1000)
					AND 1 = CASE 
						WHEN ISNULL(S.Is_Small_Order, 0) = ISNULL(@Is_Small_Order, 0)
							OR ISNULL(S.Is_Small_Order, 0) = 0
							THEN 1
						ELSE 0
						END
					AND 1 = CASE 
						WHEN ISNULL(S.IsPadPrint, 0) = ISNULL(@IsPadPrint, 0)
							OR ISNULL(S.IsPadPrint, 0) = 0
							THEN 1
						ELSE 0
						END
					AND ISNULL(S.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
					AND ISNULL(S.First_Table, 0) = ISNULL(@IsFirstTable, 0)
					AND ISNULL(SpreadMachine_No, '') = ''
				ORDER BY ISNULL(S.Is_Now, 0) DESC
					,CASE 
						WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
							THEN 0
						ELSE 1
						END
					,isnull(Order_Status_Type, 99)
					,CASE 
						WHEN isnull(Order_Status_Type, 99) = 2
							THEN S.SeqNO
						ELSE 999
						END
					,PLAN_DATE
					,[IsEnough_Material] DESC
					,CASE 
						WHEN isnull(Paper_Sample, '') <> ''
							THEN 0
						ELSE 1
						END
					,CASE 
						WHEN isnull(Bar_Code, '') <> ''
							THEN 0
						ELSE 1
						END
					,[Priority_Level]
					--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
					,ISNULL(IS_Last_Cut, 0)
					,CASE 
						WHEN @IsFirst = 1 --当前床首床
							THEN S.pull_date_min --取最小
						ELSE (
								SELECT TOP 1 ABS(S.pull_date_min - DM.pull_date_min)
								FROM #Plan_Pull_Date_Min DM
								WHERE DM.PLAN_DATE = S.PLAN_DATE
								) --最接近优先
						END

				IF @RID <> ''
				BEGIN
					UPDATE S
					SET S.CaseNo = 3
					FROM #SPD_Order_Scheduling_idx S
					WHERE S.RID = @RID

					--SELECT @JsonStr = ''
					--SELECT @JsonStr = (
					--		SELECT S.*
					--		FROM #SPD_Order_Scheduling_idx S
					--		WHERE rid = @RID
					--		FOR JSON PATH
					--		)
					--SELECT @Action_Message = N'确定顺序位置'
					--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
					--	,@Action_ID = 'JobSeq'
					--	,@Action_Type = 'SetCaseNo'
					--	,@Action_Message = @Action_Message
					SELECT @Action_ID = 'JobSeq'
						,@Action_Type = 'SetCaseNo'

					--,@Action_Message = @Cut_Action_Message
					INSERT INTO #SPD_Order_Scheduling_log (
						RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID
						,Action_Type
						,Action_Date
						,Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
						)
					SELECT RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID = @Action_ID
						,Action_Type = @Action_Type
						,Action_Date = GETDATE()
						,Action_Message = @Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No = SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
					FROM #SPD_Order_Scheduling_idx
					WHERE RID = @RID
				END
			END

			IF @RID <> ''
			BEGIN
				UPDATE S
				SET S.CaseNo = 4
				FROM #SPD_Order_Scheduling_idx S
				WHERE S.RID = @RID

				--SELECT @JsonStr = ''
				--SELECT @JsonStr = (
				--		SELECT S.*
				--		FROM #SPD_Order_Scheduling_idx S
				--		WHERE rid = @RID
				--		FOR JSON PATH
				--		)
				--SELECT @Action_Message = N'确定顺序位置'
				--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
				--	,@Action_ID = 'JobSeq'
				--	,@Action_Type = 'SetCaseNo'
				--	,@Action_Message = @Action_Message
				SELECT @Action_ID = 'JobSeq'
					,@Action_Type = 'SetCaseNo'

				--,@Action_Message = @Cut_Action_Message
				INSERT INTO #SPD_Order_Scheduling_log (
					RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID
					,Action_Type
					,Action_Date
					,Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
					)
				SELECT RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID = @Action_ID
					,Action_Type = @Action_Type
					,Action_Date = GETDATE()
					,Action_Message = @Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No = SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx
				WHERE RID = @RID
			END

			--AND ISNULL(CaseNo, 0) = 0
			IF @Spread_Plan_Date > @Work_Date
				AND ISNULL(@RID, '') <> ''
			BEGIN
				PRINT N'CurrentDate=' + CONVERT(VARCHAR(50), @CurrentDate, 21) + N' 当前拉布机没有当天了，找其他拉布机还有没有：@SpreadMachine_No=' + ISNULL(@SpreadMachine_No, '') + ',@RID=' + ISNULL(@RID, '') + ',@Spread_Plan_Date' + CONVERT(VARCHAR(50), @Spread_Plan_Date, 21)

				SELECT @Cut_SeqNO = 1

				SELECT TOP 1 @Cut_SeqNO = Seq_NO
				FROM Tb_CutMachine WITH (NOLOCK)
				WHERE CutMachine_No = @CutMachine_No

				IF object_id('tempdb..#SPD_Order_Scheduling_Work_Date') IS NOT NULL
					DROP TABLE #SPD_Order_Scheduling_Work_Date

				SELECT TOP 1 S.*
				INTO #SPD_Order_Scheduling_Work_Date
				FROM #SPD_Order_Scheduling_idx S
				LEFT JOIN Tb_CutMachine TC WITH (NOLOCK) ON TC.CutMachine_No = S.CutMachine_No
				WHERE ISNULL(SpreadMachine_No, '') = ''
					--AND Plan_Pull_Date_Start IS NULL
					--AND ISNULL(CutMachine_No, '') <> ''
					AND ISNULL(S.Marker_Width, 0) <= ISNULL(@Marker_Width, 1000)
					AND 1 = CASE 
						WHEN ISNULL(S.Is_Small_Order, 0) = ISNULL(@Is_Small_Order, 0)
							OR ISNULL(S.Is_Small_Order, 0) = 0
							THEN 1
						ELSE 0
						END
					AND 1 = CASE 
						WHEN ISNULL(S.IsPadPrint, 0) = ISNULL(@IsPadPrint, 0)
							OR ISNULL(S.IsPadPrint, 0) = 0
							THEN 1
						ELSE 0
						END
					AND ISNULL(S.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
					AND ISNULL(S.First_Table, 0) = ISNULL(@IsFirstTable, 0)
					AND PLAN_DATE = @Work_Date
					AND isnull(Order_Status_Type, 99) > 3
				ORDER BY ISNULL(S.Is_Now, 0) DESC
					,CASE 
						WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
							THEN 0
						ELSE 1
						END
					,isnull(Order_Status_Type, 99)
					,CASE 
						WHEN isnull(Order_Status_Type, 99) = 2
							THEN S.SeqNO
						ELSE 999
						END
					,PLAN_DATE
					,[IsEnough_Material] DESC
					,CASE 
						WHEN isnull(Paper_Sample, '') <> ''
							THEN 0
						ELSE 1
						END
					,CASE 
						WHEN isnull(Bar_Code, '') <> ''
							THEN 0
						ELSE 1
						END
					,[Priority_Level]
					--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
					,ISNULL(IS_Last_Cut, 0)
					,ABS(ISNULL(TC.Seq_NO, 0) - ISNULL(@Cut_SeqNO, 0))
					,CASE 
						WHEN @IsFirst = 1 --当前床首床
							THEN S.pull_date_min --取最小
						ELSE (
								SELECT TOP 1 ABS(S.pull_date_min - DM.pull_date_min)
								FROM #Plan_Pull_Date_Min DM
								WHERE DM.PLAN_DATE = S.PLAN_DATE
								) --最接近优先
						END

				IF EXISTS (
						SELECT TOP 1 1
						FROM #SPD_Order_Scheduling_Work_Date
						)
				BEGIN
					SELECT TOP 1 @RID = RID
						,@Adjust_Machine_No = Adjust_Machine_No
						,@SO_No = SO_No
						,@Batch_No = Batch_No
						,@Spread_Plan_Date = Plan_Date
						--,@Marker_Width = ISNULL(Marker_Width, 0)
						--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
						,@CutMachine_No = CutMachine_No
						,@IS_Last_Cut = IS_Last_Cut
						,@IS_Merge_Cut = IS_Merge_Cut
						,@Ori_Plan_Date = Ori_Plan_Date
						,@MO_NO = MO_NO
						,@Merge_Cut_Remark = Merge_Cut_Remark
						,@Assigned_SpreadMachine_No = SpreadMachine_No
						,@Table_No = Table_No
						,@Spd_Type = Spd_Type
						,@Order_Status_Type = Order_Status_Type
						,@Cut_date_Min = cut_date_Min
						,@IsStripe = S.IsStripe
						,@IsPadPrint = S.IsPadPrint
						,@IsAbnormal = S.IsAbnormal
						,@IsFirstTable = S.First_Table
					FROM #SPD_Order_Scheduling_Work_Date S

					PRINT N'CurrentDate=' + CONVERT(VARCHAR(50), @CurrentDate, 21) + N' 当前拉布机没有当天了，找到其他拉布机有：@SpreadMachine_No=' + ISNULL(@SpreadMachine_No, '') + ',@RID=' + ISNULL(@RID, '') + ',@Spread_Plan_Date' + CONVERT(VARCHAR(50), @Spread_Plan_Date, 21) + ',@CutMachine_No=' + isnull(@CutMachine_No, '')

					SELECT @Action_Message = N'CurrentDate=' + CONVERT(VARCHAR(50), @CurrentDate, 21) + N' 当前拉布机没有当天了，找到其他拉布机有：@SpreadMachine_No=' + ISNULL(@SpreadMachine_No, '') + ',@RID=' + ISNULL(@RID, '') + ',@Spread_Plan_Date' + CONVERT(VARCHAR(50), @Spread_Plan_Date, 21) + ',@CutMachine_No=' + isnull(@CutMachine_No, '')

					IF @RID <> ''
					BEGIN
						UPDATE S
						SET S.CaseNo = 5
						FROM #SPD_Order_Scheduling_idx S
						WHERE S.RID = @RID

						--SELECT @JsonStr = ''
						--SELECT @JsonStr = (
						--		SELECT S.*
						--		FROM #SPD_Order_Scheduling_idx S
						--		WHERE rid = @RID
						--		FOR JSON PATH
						--		)
						--SELECT @Action_Message = N'确定顺序位置,' + @Action_Message
						--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
						--	,@Action_ID = 'JobSeq'
						--	,@Action_Type = 'SetCaseNo'
						--	,@Action_Message = @Action_Message
						SELECT @Action_ID = 'JobSeq'
							,@Action_Type = 'SetCaseNo'

						--,@Action_Message = @Cut_Action_Message
						INSERT INTO #SPD_Order_Scheduling_log (
							RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID
							,Action_Type
							,Action_Date
							,Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
							)
						SELECT RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID = @Action_ID
							,Action_Type = @Action_Type
							,Action_Date = GETDATE()
							,Action_Message = @Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No = SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
						FROM #SPD_Order_Scheduling_idx
						WHERE RID = @RID
					END
				END
			END

			IF ISNULL(@RID, '') = ''
			BEGIN
				--自己裁剪机找不到则到别的裁剪机找
				SELECT TOP 1 @RID = RID
					,@Adjust_Machine_No = Adjust_Machine_No
					,@SO_No = SO_No
					,@Batch_No = Batch_No
					,@Spread_Plan_Date = Plan_Date
					--,@Marker_Width = ISNULL(Marker_Width, 0)
					--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
					,@CutMachine_No = CutMachine_No
					,@IS_Last_Cut = IS_Last_Cut
					,@IS_Merge_Cut = IS_Merge_Cut
					,@Ori_Plan_Date = Ori_Plan_Date
					,@MO_NO = MO_NO
					,@Merge_Cut_Remark = Merge_Cut_Remark
					,@Assigned_SpreadMachine_No = SpreadMachine_No
					,@Table_No = Table_No
					,@Spd_Type = Spd_Type
					,@Order_Status_Type = Order_Status_Type
					,@Cut_date_Min = cut_date_Min
				FROM #SPD_Order_Scheduling_idx S
				WHERE --ISNULL(SpreadMachine_No, '') = ''
					Plan_Pull_Date_Start IS NULL
					AND ISNULL(CutMachine_No, '') <> ''
					AND ISNULL(S.Marker_Width, 0) <= ISNULL(@Marker_Width, 1000)
					AND 1 = CASE 
						WHEN ISNULL(S.Is_Small_Order, 0) = ISNULL(@Is_Small_Order, 0)
							OR ISNULL(S.Is_Small_Order, 0) = 0
							THEN 1
						ELSE 0
						END
					AND 1 = CASE 
						WHEN ISNULL(S.IsPadPrint, 0) = ISNULL(@IsPadPrint, 0)
							OR ISNULL(S.IsPadPrint, 0) = 0
							THEN 1
						ELSE 0
						END
					AND ISNULL(S.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
					AND ISNULL(S.First_Table, 0) = ISNULL(@IsFirstTable, 0)
				ORDER BY ISNULL(S.Is_Now, 0) DESC
					,CASE 
						WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
							THEN 0
						ELSE 1
						END
					,isnull(Order_Status_Type, 99)
					,CASE 
						WHEN isnull(Order_Status_Type, 99) = 2
							THEN S.SeqNO
						ELSE 999
						END
					,PLAN_DATE
					,[IsEnough_Material] DESC
					,CASE 
						WHEN isnull(Paper_Sample, '') <> ''
							THEN 0
						ELSE 1
						END
					,CASE 
						WHEN isnull(Bar_Code, '') <> ''
							THEN 0
						ELSE 1
						END
					,[Priority_Level]
					--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
					,ISNULL(IS_Last_Cut, 0)
					,CASE 
						WHEN @IsFirst = 1 --当前床首床
							THEN S.pull_date_min --取最小
						ELSE (
								SELECT TOP 1 ABS(S.pull_date_min - DM.pull_date_min)
								FROM #Plan_Pull_Date_Min DM
								WHERE DM.PLAN_DATE = S.PLAN_DATE
								) --最接近优先
						END

				IF @RID <> ''
				BEGIN
					UPDATE S
					SET S.CaseNo = 6
					FROM #SPD_Order_Scheduling_idx S
					WHERE S.RID = @RID

					--SELECT @JsonStr = ''
					--SELECT @JsonStr = (
					--		SELECT S.*
					--		FROM #SPD_Order_Scheduling_idx S
					--		WHERE rid = @RID
					--		FOR JSON PATH
					--		)
					--SELECT @Action_Message = N'确定顺序位置'
					--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
					--	,@Action_ID = 'JobSeq'
					--	,@Action_Type = 'SetCaseNo'
					--	,@Action_Message = @Action_Message
					SELECT @Action_ID = 'JobSeq'
						,@Action_Type = 'SetCaseNo'
						,@Action_Message = N'确定顺序位置'

					INSERT INTO #SPD_Order_Scheduling_log (
						RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID
						,Action_Type
						,Action_Date
						,Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
						)
					SELECT RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID = @Action_ID
						,Action_Type = @Action_Type
						,Action_Date = GETDATE()
						,Action_Message = @Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No = SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
					FROM #SPD_Order_Scheduling_idx
					WHERE RID = @RID
				END
			END

			IF ISNULL(@RID, '') = ''
			BEGIN
				SELECT TOP 1 @RID = RID
					,@Adjust_Machine_No = Adjust_Machine_No
					,@SO_No = SO_No
					,@Batch_No = Batch_No
					,@Spread_Plan_Date = Plan_Date
					,@Marker_Width = ISNULL(Marker_Width, 0)
					,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
					,@CutMachine_No = CutMachine_No
					,@IS_Last_Cut = IS_Last_Cut
					,@IS_Merge_Cut = IS_Merge_Cut
					,@Ori_Plan_Date = Ori_Plan_Date
					,@MO_NO = MO_NO
					,@Merge_Cut_Remark = Merge_Cut_Remark
					,@Assigned_SpreadMachine_No = SpreadMachine_No
					,@Table_No = Table_No
					,@Spd_Type = Spd_Type
					,@Order_Status_Type = Order_Status_Type
					,@Cut_date_Min = cut_date_Min
					,@IsStripe = S.IsStripe
					,@IsPadPrint = S.IsPadPrint
					,@IsAbnormal = S.IsAbnormal
					,@IsFirstTable = S.First_Table
				FROM #SPD_Order_Scheduling_idx S
				WHERE --ISNULL(SpreadMachine_No, '') = ''
					Plan_Pull_Date_Start IS NULL
					AND ISNULL(CutMachine_No, '') <> ''
				--AND ISNULL(S.Marker_Width, 0) <= ISNULL(@Marker_Width, 1000)
				--AND 1 = CASE 
				--	WHEN ISNULL(S.Is_Small_Order, 0) = ISNULL(@Is_Small_Order, 0)
				--		OR ISNULL(S.Is_Small_Order, 0) = 0
				--		THEN 1
				--	ELSE 0
				--	END
				ORDER BY ISNULL(S.Is_Now, 0) DESC
					,CASE 
						WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
							THEN 0
						ELSE 1
						END
					,isnull(Order_Status_Type, 99)
					,CASE 
						WHEN isnull(Order_Status_Type, 99) = 2
							THEN S.SeqNO
						ELSE 999
						END
					,PLAN_DATE
					,[IsEnough_Material] DESC
					,CASE 
						WHEN isnull(Paper_Sample, '') <> ''
							THEN 0
						ELSE 1
						END
					,CASE 
						WHEN isnull(Bar_Code, '') <> ''
							THEN 0
						ELSE 1
						END
					,[Priority_Level]
					--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
					,ISNULL(IS_Last_Cut, 0)

				IF object_id('tempdb..#pull_date_Min_Small_Order') IS NOT NULL
					DROP TABLE #pull_date_Min_Small_Order

				--PRINT '2157:@CutMachine_No=' + isnull(@CutMachine_No, 0)
				SELECT SpreadMachine_No = ISNULL(SpreadMachine_No, '')
					,pull_date_Min = SUM(isnull(pull_date_Min, 0))
				INTO #pull_date_Min_Small_Order
				FROM #SPD_Order_Scheduling_idx
				WHERE ISNULL(SpreadMachine_No, '') <> ''
					AND ISNULL(Order_Status_Type, 0) > 0
				--AND @Is_Small_Order = Is_Small_Order
				--OR @Is_Small_Order = 0
				GROUP BY ISNULL(SpreadMachine_No, '')

				INSERT INTO #pull_date_Min_Small_Order (
					SpreadMachine_No
					,pull_date_Min
					)
				SELECT DISTINCT M.SpreadMachine_No
					,pull_date_Min = 0
				FROM #TB_SpreadMachine M WITH (NOLOCK)
				LEFT JOIN #pull_date_Min C ON M.SpreadMachine_No = C.SpreadMachine_No
				--AND ISNULL(M.Valid_Status, 0) = 1
				WHERE C.SpreadMachine_No IS NULL
					--AND isnull(M.CutMachine_No, '') = @CutMachine_No
					AND ISNULL(M.Valid_Status, 0) = 1

				--AND (
				--	@Is_Small_Order = Is_Small_Order
				--	OR Is_Small_Order = 1
				--	)
				DELETE S
				FROM #pull_date_Min_Small_Order S
				WHERE SpreadMachine_No NOT IN (
						SELECT SpreadMachine_No
						FROM #TB_SpreadMachine M -- WITH (NOLOCK)
						WHERE ISNULL(M.Valid_Status, 0) = 1
							AND (
								ISNULL(@Is_Small_Order, 0) = ISNULL(M.Is_Small_Order, 0)
								OR ISNULL(M.Is_Small_Order, 0) = 1
								)
							AND (
								ISNULL(@IsPadPrint, 0) = ISNULL(M.IsPadPrint, 0)
								OR ISNULL(M.IsPadPrint, 0) = 1
								)
							AND ISNULL(M.IsAbnormal, 0) = ISNULL(@IsAbnormal, 0)
							AND ISNULL(M.IsFirstTable, 0) = ISNULL(@IsFirstTable, 0)
							AND ISNULL(@Marker_Width, 0) <= ISNULL(M.Marker_Width, 1000)
						)

				SELECT TOP 1 @SpreadMachine_No = P.SpreadMachine_No
				FROM #pull_date_Min_Small_Order p
				INNER JOIN #TB_SpreadMachine S ON P.SpreadMachine_No = S.SpreadMachine_No
				ORDER BY pull_date_Min

				IF @RID <> ''
				BEGIN
					UPDATE S
					SET S.CaseNo = 7
					FROM #SPD_Order_Scheduling_idx S
					WHERE S.RID = @RID

					--SELECT @JsonStr = ''
					--SELECT @JsonStr = (
					--		SELECT S.*
					--		FROM #SPD_Order_Scheduling_idx S
					--		WHERE rid = @RID
					--		FOR JSON PATH
					--		)
					--SELECT @Action_Message = N'确定顺序位置'
					--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
					--	,@Action_ID = 'JobSeq'
					--	,@Action_Type = 'SetCaseNo'
					--	,@Action_Message = @Action_Message
					SELECT @Action_ID = 'JobSeq'
						,@Action_Type = 'SetCaseNo'
						,@Action_Message = N'确定顺序位置'

					INSERT INTO #SPD_Order_Scheduling_log (
						RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID
						,Action_Type
						,Action_Date
						,Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
						)
					SELECT RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID = @Action_ID
						,Action_Type = @Action_Type
						,Action_Date = GETDATE()
						,Action_Message = @Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No = SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
					FROM #SPD_Order_Scheduling_idx
					WHERE RID = @RID
				END
				ELSE
				BEGIN
					INSERT INTO #SPD_Order_Scheduling_log (
						RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID
						,Action_Type
						,Action_Date
						,Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						)
					SELECT RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID = 'BreakMessage7'
						,Action_Type = 'BreakMessage7'
						,Action_Date = GETDATE()
						,Action_Message = 'BreakMessage7'
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No = NULL
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
					FROM #SPD_Order_Scheduling_idx

					INSERT INTO LOGS (
						RID
						,UserID
						,ActionTime
						,FullURL
						,Source
						,StackTrace
						,Message
						,LogType
						)
					SELECT RID = CONVERT(VARCHAR(50), NEWID())
						,UserID = CONVERT(VARCHAR(50), ISNULL(@Marker_Width, 0))
						,ActionTime = GETDATE()
						,FullURL = 'BreakMessage7'
						,Source = (
							SELECT *
							FROM #TB_SpreadMachine
							FOR JSON PATH
							)
						,StackTrace = @Calculate_LotNumber
						,Message = '@Is_Small_Order=' + CONVERT(VARCHAR(20), ISNULL(@Is_Small_Order, 0))
						,LogType = convert(VARCHAR(50), @Quit_Index)
				END
			END

			SELECT @RID_24 = ''
				,@Quit_Index2 = 1
				,@Ori_SPD_RID = @RID

			--DELETE
			--FROM @Batch_List
			--判断是否合缸 Damon gu 2025-04-10
			WHILE @Quit_Index2 <= 1000
				AND ISNULL(@RID_24, '') <> ISNULL(@RID, '')
				AND (
					(
						ISNULL(@Batch_No, '') <> ''
						AND ISNULL(@RID, '') <> ''
						AND isnull(@Order_Status_Type, 99) > 1
						--AND CHARINDEX(';', @Batch_No) > 0
						AND EXISTS (
							SELECT TOP 1 1
							FROM SPD_Merge_Table_Info WITH (NOLOCK)
							WHERE Data_Type = 'MergeBatch'
								AND Mst_RID = @RID
							)
						)
					OR (
						ISNULL(@IS_Merge_Cut, 0) = 1
						AND ISNULL(@RID, '') <> ''
						AND isnull(@Order_Status_Type, 99) > 1
						)
					OR (
						ISNULL(@IS_Last_Cut, 0) = 1
						AND ISNULL(@RID, '') <> ''
						AND isnull(@Order_Status_Type, 99) > 1
						)
					)
			BEGIN
				SELECT @RID_24 = @RID
					,@Quit_Index2 = @Quit_Index2 + 1

				--SELECT @JsonStr = ''
				--SELECT @JsonStr = (
				--		SELECT S.*
				--		FROM #SPD_Order_Scheduling_idx S
				--		WHERE rid = @RID_24
				--		FOR JSON PATH
				--		)
				SELECT @Action_Message = N'循环找特殊@Quit_Index2=' + convert(VARCHAR(50), @Quit_Index2) + ',@RID_24=' + isnull(@RID_24, '') + ',@Quit_Index=' + convert(VARCHAR(50), @Quit_Index)

				--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
				--	,@Action_ID = 'JobSeq'
				--	,@Action_Type = 'WhileLastCut&MergeCut'
				--	,@Action_Message = @Action_Message
				SELECT @Action_ID = 'JobSeq'
					,@Action_Type = 'WhileLastCut&MergeCut'

				--,@Action_Message = @Cut_Action_Message
				INSERT INTO #SPD_Order_Scheduling_log (
					RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID
					,Action_Type
					,Action_Date
					,Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
					)
				SELECT RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID = @Action_ID
					,Action_Type = @Action_Type
					,Action_Date = GETDATE()
					,Action_Message = @Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No = SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx
				WHERE rid = @RID_24

				IF ISNULL(@Batch_No, '') <> ''
					AND ISNULL(@RID, '') <> ''
					AND isnull(@Order_Status_Type, 99) > 1
					--AND CHARINDEX(';', @Batch_No) > 0
					AND EXISTS (
						SELECT TOP 1 1
						FROM SPD_Merge_Table_Info WITH (NOLOCK)
						WHERE Data_Type = 'MergeBatch'
							AND Mst_RID = @RID
						)
				BEGIN
					--INSERT INTO @Batch_List (Batch_No)
					--SELECT Batch_No = value
					--FROM STRING_SPLIT(@Batch_No, ';') d
					--UPDATE S
					--SET S.Merge_RID = @RID
					--FROM #SPD_Order_Scheduling_idx S
					--INNER JOIN @Batch_List M ON CONVERT(VARCHAR(20), S.Batch_No) = M.Batch_No
					--WHERE SO_NO = @SO_NO --2025-03-31 已和tony&cassie确认，合拉BY MO
					--	AND Ori_Plan_Date = @Ori_Plan_Date
					--UPDATE S
					--SET S.Merge_RID = @RID
					--FROM #SPD_Order_Scheduling_idx S
					--WHERE RID = @RID
					UPDATE S
					SET S.Merge_RID = @RID
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M ON Data_Type = 'MergeBatch'
						AND M.Dtl_RID = S.RID
						AND M.MST_RID = @RID --CONVERT(VARCHAR(20), S.TABLE_NO) = M.TABLE_NO
						--WHERE MO_NO = @MO_NO --2025-03-31 已和tony&cassie确认，合拉BY MO
						--AND Ori_Plan_Date = @Ori_Plan_Date

					UPDATE S
					SET S.Merge_RID = @RID
					FROM #SPD_Order_Scheduling_idx S
					WHERE RID = @RID

					IF object_id('tempdb..#SPD_Order_Scheduling_MergeBatch') IS NOT NULL
						DROP TABLE #SPD_Order_Scheduling_MergeBatch

					SELECT TOP 1 S.*
					INTO #SPD_Order_Scheduling_MergeBatch
					FROM #SPD_Order_Scheduling_idx S
					--LEFT JOIN SPD_Merge_Table_Info M ON M.Data_Type = 'MergeBatch' AND S.RID = M.Mst_RID
					WHERE ISNULL(S.IS_Merge_Cut, 0) = 0
						AND S.RID <> @RID
						AND CHARINDEX(';', S.Batch_NO) <= 0
						AND isnull(S.Merge_RID, '') = @RID
						AND S.Order_Status_Type >= 1
						AND S.Plan_Pull_Date_Start IS NULL
					--AND Ori_Plan_Date = @Ori_Plan_Date --Damon gu 2025-02-27 每天都有后拉，所以只和计划天数相同的非后拉合，CASSIE
					ORDER BY ISNULL(S.Is_Now, 0) DESC
						,CASE 
							WHEN ISNULL(S.SpreadMachine_No, '') = @SpreadMachine_No
								THEN 0
							ELSE 1
							END
						,isnull(S.Order_Status_Type, 99)
						,CASE 
							WHEN isnull(S.Order_Status_Type, 99) = 2
								THEN S.SeqNO
							ELSE 999
							END
						,S.PLAN_DATE
						,S.[IsEnough_Material] DESC
						,CASE 
							WHEN isnull(S.Paper_Sample, '') <> ''
								THEN 0
							ELSE 1
							END
						,CASE 
							WHEN isnull(S.Bar_Code, '') <> ''
								THEN 0
							ELSE 1
							END
						,S.[Priority_Level]
						--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
						,ISNULL(S.IS_Last_Cut, 0)

					IF EXISTS (
							SELECT TOP 1 1
							FROM #SPD_Order_Scheduling_MergeBatch
							)
					BEGIN
						--SELECT @JsonStr = ''
						--SELECT @JsonStr = (
						--		SELECT TOP 1 *
						--		FROM #SPD_Order_Scheduling_idx
						--		WHERE RID = @RID
						--		FOR JSON PATH
						--		)
						SELECT TOP 1 @RID = RID
							,@Adjust_Machine_No = Adjust_Machine_No
							,@SO_No = SO_No
							,@Batch_No = Batch_No
							,@Spread_Plan_Date = Plan_Date
							--,@Marker_Width = ISNULL(Marker_Width, 0)
							--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
							,@CutMachine_No = CutMachine_No
							,@IS_Last_Cut = IS_Last_Cut
							,@IS_Merge_Cut = IS_Merge_Cut
							,@Ori_Plan_Date = Ori_Plan_Date
							,@MO_NO = MO_NO
							,@Merge_Cut_Remark = Merge_Cut_Remark
							,@Assigned_SpreadMachine_No = SpreadMachine_No
							,@Table_No = Table_No
							,@Spd_Type = Spd_Type
							,@Order_Status_Type = Order_Status_Type
							,@Cut_date_Min = cut_date_Min
						FROM #SPD_Order_Scheduling_MergeBatch

						DECLARE @MessageLastCut1151 NVARCHAR(MAX) = N'有其他非合缸床次RID=' + @RID

						--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
						--	,@Action_ID = 'JobSeq'
						--	,@Action_Type = 'MergeBatchLastCut'
						--	,@Action_Message = @MessageLastCut1151 --N'有其他非后拉床次'
						SELECT @Action_ID = 'JobSeq'
							,@Action_Type = 'MergeBatchLastCut'
							,@Action_Message = @MessageLastCut1151

						INSERT INTO #SPD_Order_Scheduling_log (
							RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID
							,Action_Type
							,Action_Date
							,Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
							)
						SELECT RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID = @Action_ID
							,Action_Type = @Action_Type
							,Action_Date = GETDATE()
							,Action_Message = @Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No = SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
						FROM #SPD_Order_Scheduling_idx
						WHERE RID = @RID

						IF @RID <> ''
						BEGIN
							UPDATE S
							SET S.CaseNo = 8
							FROM #SPD_Order_Scheduling_idx S
							WHERE S.RID = @RID

							--SELECT @JsonStr = ''
							--SELECT @JsonStr = (
							--		SELECT S.*
							--		FROM #SPD_Order_Scheduling_idx S
							--		WHERE rid = @RID
							--		FOR JSON PATH
							--		)
							SELECT @Action_Message = N'确定顺序位置'

							--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
							--	,@Action_ID = 'JobSeq'
							--	,@Action_Type = 'SetCaseNo'
							--	,@Action_Message = @Action_Message
							SELECT @Action_ID = 'JobSeq'
								,@Action_Type = 'SetCaseNo'

							--,@Action_Message = @Cut_Action_Message
							INSERT INTO #SPD_Order_Scheduling_log (
								RID
								,Plan_Date
								,Ori_Plan_Date
								,SpreadMachine_No
								,CutMachine_No
								,Case_Category
								,CaseNo
								,SeqNO
								,MO_NO
								,Spd_Type
								,Table_NO
								,Color_Code
								,Color_Desc
								,SO_No
								,Batch_No
								,Plan_Layer_Qty
								,Act_Layer_Qty
								,pull_date_Min
								,cut_date_Min
								,Plan_Pull_Date_Start
								,Plan_Pull_Date_End
								,Act_Pull_Date_Start
								,Act_Pull_Date_End
								,Plan_Cut_Date_Start
								,Plan_Cut_Date_End
								,Act_Cut_Date_Start
								,Act_Cut_Date_End
								,Used_Length
								,Allocate_Length
								,Input_Length
								,Rest_Minute
								,Cut_SeqNO
								,Can_Cut_Date
								,Can_Spread_Date
								,Create_Date
								,Paper_Sample
								,First_Table
								,QRTYPE
								,QR_Seq
								,Other_Main_Rid
								,IS_Last_Cut
								,Last_Cut_RID
								,Order_Status
								,Order_Status_Type
								,AddStatus
								,AddStatus_Type
								,IS_ALL_Cut
								,Priority_Level
								,Adjust_Machine_No
								,Adjust_Time
								,IS_Old_Table
								,IS_Merge_Cut
								,Merge_Cut_Remark
								,Merge_RID
								,Spread_Scan_Time
								,IsLock
								,Lot_Number_Calculate
								,IsEnough_Material
								,Action_ID
								,Action_Type
								,Action_Date
								,Action_Message
								,Group_Lot_Number
								,Marker_Width
								,Adjust_Start_Time
								,Is_Small_Order
								,Merge_Cut_RID
								,Ori_SpreadMachine_No
								,IsChao
								,Bar_Code
								,Is_Cut
								,Is_Now
								,IsStripe
								,IsPadPrint
								,IsAbnormal
								,Marker_No
								,Group_RID
								,PadPrinting_Together_RID
								)
							SELECT RID
								,Plan_Date
								,Ori_Plan_Date
								,SpreadMachine_No
								,CutMachine_No
								,Case_Category
								,CaseNo
								,SeqNO
								,MO_NO
								,Spd_Type
								,Table_NO
								,Color_Code
								,Color_Desc
								,SO_No
								,Batch_No
								,Plan_Layer_Qty
								,Act_Layer_Qty
								,pull_date_Min
								,cut_date_Min
								,Plan_Pull_Date_Start
								,Plan_Pull_Date_End
								,Act_Pull_Date_Start
								,Act_Pull_Date_End
								,Plan_Cut_Date_Start
								,Plan_Cut_Date_End
								,Act_Cut_Date_Start
								,Act_Cut_Date_End
								,Used_Length
								,Allocate_Length
								,Input_Length
								,Rest_Minute
								,Cut_SeqNO
								,Can_Cut_Date
								,Can_Spread_Date
								,Create_Date
								,Paper_Sample
								,First_Table
								,QRTYPE
								,QR_Seq
								,Other_Main_Rid
								,IS_Last_Cut
								,Last_Cut_RID
								,Order_Status
								,Order_Status_Type
								,AddStatus
								,AddStatus_Type
								,IS_ALL_Cut
								,Priority_Level
								,Adjust_Machine_No
								,Adjust_Time
								,IS_Old_Table
								,IS_Merge_Cut
								,Merge_Cut_Remark
								,Merge_RID
								,Spread_Scan_Time
								,IsLock
								,Lot_Number_Calculate
								,IsEnough_Material
								,Action_ID = @Action_ID
								,Action_Type = @Action_Type
								,Action_Date = GETDATE()
								,Action_Message = @Action_Message
								,Group_Lot_Number
								,Marker_Width
								,Adjust_Start_Time
								,Is_Small_Order
								,Merge_Cut_RID
								,Ori_SpreadMachine_No = SpreadMachine_No
								,IsChao
								,Bar_Code
								,Is_Cut
								,Is_Now
								,IsStripe
								,IsPadPrint
								,IsAbnormal
								,Marker_No
								,Group_RID
								,PadPrinting_Together_RID
							FROM #SPD_Order_Scheduling_idx
							WHERE RID = @RID
						END
					END
					ELSE
					BEGIN
						--重新找到最后的拉布机
						SELECT @LastCut_SpreadMachine_No = ''
							,@LastCut_CutMachine_No = ''
							,@RID_26 = ''

						SELECT TOP 1 @LastCut_SpreadMachine_No = SpreadMachine_No
							,@LastCut_CutMachine_No = CutMachine_No
							--,@Plan_Pull_Date_Start = Plan_Pull_Date_End
							,@RID_26 = S.RID
						FROM #SPD_Order_Scheduling_idx S
						INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.MST_RID = @RID
							AND M.DTL_RID = S.RID
						--INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M2.Data_Type
						--	AND M2.MST_RID = M.MST_RID
						--	AND M2.DTL_RID = S.RID
						WHERE M.Data_Type = 'MergeBatch'
							AND S.Plan_Pull_Date_Start IS NOT NULL
						ORDER BY S.Plan_Pull_Date_End DESC

						IF ISNULL(@LastCut_SpreadMachine_No, '') <> ''
						BEGIN
							SELECT @SpreadMachine_No = @LastCut_SpreadMachine_No
								,@CutMachine_No = @LastCut_CutMachine_No
						END

						--UPDATE S
						--SET SpreadMachine_No = @LastCut_SpreadMachine_No
						--	,CutMachine_No = @LastCut_CutMachine_No
						--	,S.Is_Now = 1
						--FROM #SPD_Order_Scheduling_idx S
						--INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
						--	AND M.MST_RID = S.RID
						--WHERE Data_Type = 'MergeBatch'
						SELECT @RID_25 = ''

						--SELECT TOP 1 @RID_25 = RID
						--FROM #SPD_Order_Scheduling_idx S
						--WHERE @LastCut_SpreadMachine_No = SpreadMachine_No
						--	AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
						--	AND Plan_Date = @Spread_Plan_Date
						--ORDER BY Plan_Pull_Date_Start DESC
						--SELECT @JsonStr = ''
						--SELECT @JsonStr = (
						--		SELECT S.*
						--		FROM #SPD_Order_Scheduling_idx S
						--		INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = S.RID
						--			AND M.MST_RID = @RID
						--		WHERE Data_Type = 'MergeBatch'
						--		FOR JSON PATH
						--		)
						SELECT @Action_Message = N'合缸锁定在@RID_26=' + ISNULL(@RID_26, '') + N'后面,原后面存在@RID_25=' + ISNULL(@RID_25, '')

						--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
						--	,@Action_ID = 'JobSeq'
						--	,@Action_Type = 'MergeBatchLock1'
						--	,@Action_Message = @Action_Message
						SELECT @Action_ID = 'JobSeq'
							,@Action_Type = 'MergeBatchLock1'

						--,@Action_Message = @Cut_Action_Message
						INSERT INTO #SPD_Order_Scheduling_log (
							RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID
							,Action_Type
							,Action_Date
							,Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
							)
						SELECT S.RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,S.Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID = @Action_ID
							,Action_Type = @Action_Type
							,Action_Date = GETDATE()
							,Action_Message = @Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No = SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
						FROM #SPD_Order_Scheduling_idx S
						INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = S.RID
							AND M.MST_RID = @RID
						WHERE Data_Type = 'MergeBatch'
					END
				END

				IF ISNULL(@IS_Merge_Cut, 0) = 1
					AND ISNULL(@RID, '') <> ''
					AND isnull(@Order_Status_Type, 99) > 1
				BEGIN
					--DELETE
					--FROM @Merge_Table
					--INSERT INTO @Merge_Table (Table_No)
					--SELECT string
					--FROM dbo.uf_StrSplit(@Merge_Cut_Remark, '/')
					UPDATE S
					SET S.Merge_Cut_RID = @RID
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M ON Data_Type = 'MergeCut'
						AND M.Dtl_RID = S.RID
						AND M.MST_RID = @RID --CONVERT(VARCHAR(20), S.TABLE_NO) = M.TABLE_NO
						--WHERE MO_NO = @MO_NO --2025-03-31 已和tony&cassie确认，合拉BY MO
						--AND Ori_Plan_Date = @Ori_Plan_Date

					UPDATE S
					SET S.Merge_Cut_RID = @RID
					FROM #SPD_Order_Scheduling_idx S
					WHERE RID = @RID

					--SO_NO = @SO_NO
					--	AND Batch_No = @Batch_No
					--	--AND ISNULL(S.Merge_Cut_RID, '') = ''
					--	AND Ori_Plan_Date = @Ori_Plan_Date
					--AND ISNULL(S.Merge_Cut_RID, '') = ''
					IF object_id('tempdb..#SPD_Order_Scheduling_MergeCut') IS NOT NULL
						DROP TABLE #SPD_Order_Scheduling_MergeCut

					SELECT TOP 1 *
					INTO #SPD_Order_Scheduling_MergeCut
					FROM #SPD_Order_Scheduling_idx S
					WHERE ISNULL(IS_Merge_Cut, 0) = 0
						AND RID <> @RID
						AND isnull(Merge_Cut_RID, '') = @RID
						AND Order_Status_Type >= 1
						AND Plan_Pull_Date_Start IS NULL
					--AND Ori_Plan_Date = @Ori_Plan_Date --Damon gu 2025-02-27 每天都有后拉，所以只和计划天数相同的非后拉合，CASSIE
					ORDER BY ISNULL(S.Is_Now, 0) DESC
						,CASE 
							WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
								THEN 0
							ELSE 1
							END
						,isnull(Order_Status_Type, 99)
						,CASE 
							WHEN isnull(Order_Status_Type, 99) = 2
								THEN S.SeqNO
							ELSE 999
							END
						,PLAN_DATE
						,[IsEnough_Material] DESC
						,CASE 
							WHEN isnull(Paper_Sample, '') <> ''
								THEN 0
							ELSE 1
							END
						,CASE 
							WHEN isnull(Bar_Code, '') <> ''
								THEN 0
							ELSE 1
							END
						,[Priority_Level]
						--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
						,ISNULL(IS_Last_Cut, 0)

					IF EXISTS (
							SELECT TOP 1 1
							FROM #SPD_Order_Scheduling_MergeCut
							)
					BEGIN
						--SELECT @JsonStr = ''
						--SELECT @JsonStr = (
						--		SELECT TOP 1 *
						--		FROM #SPD_Order_Scheduling_idx
						--		WHERE RID = @RID
						--		FOR JSON PATH
						--		)
						SELECT TOP 1 @RID = RID
							,@Adjust_Machine_No = Adjust_Machine_No
							,@SO_No = SO_No
							,@Batch_No = Batch_No
							,@Spread_Plan_Date = Plan_Date
							--,@Marker_Width = ISNULL(Marker_Width, 0)
							--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
							,@CutMachine_No = CutMachine_No
							,@IS_Last_Cut = IS_Last_Cut
							,@IS_Merge_Cut = IS_Merge_Cut
							,@Ori_Plan_Date = Ori_Plan_Date
							,@MO_NO = MO_NO
							,@Merge_Cut_Remark = Merge_Cut_Remark
							,@Assigned_SpreadMachine_No = SpreadMachine_No
							,@Table_No = Table_No
							,@Spd_Type = Spd_Type
							,@Order_Status_Type = Order_Status_Type
							,@Cut_date_Min = cut_date_Min
						FROM #SPD_Order_Scheduling_MergeCut

						DECLARE @MessageLastCut0948 NVARCHAR(MAX) = N'有其他非后拉床次RID=' + @RID

						--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
						--	,@Action_ID = 'JobSeq'
						--	,@Action_Type = 'LastCutHaveOther'
						--	,@Action_Message = @MessageLastCut0948 --N'有其他非后拉床次'
						SELECT @Action_ID = 'JobSeq'
							,@Action_Type = 'LastCutHaveOther'
							,@Action_Message = @MessageLastCut0948 --N'有其他非后拉床次'

						INSERT INTO #SPD_Order_Scheduling_log (
							RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID
							,Action_Type
							,Action_Date
							,Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
							)
						SELECT RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID = @Action_ID
							,Action_Type = @Action_Type
							,Action_Date = GETDATE()
							,Action_Message = @Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No = SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
						FROM #SPD_Order_Scheduling_idx
						WHERE RID = @RID

						IF @RID <> ''
						BEGIN
							UPDATE S
							SET S.CaseNo = 9
							FROM #SPD_Order_Scheduling_idx S
							WHERE S.RID = @RID

							--SELECT @JsonStr = ''
							--SELECT @JsonStr = (
							--		SELECT S.*
							--		FROM #SPD_Order_Scheduling_idx S
							--		WHERE rid = @RID
							--		FOR JSON PATH
							--		)
							SELECT @Action_Message = N'确定顺序位置'

							--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
							--	,@Action_ID = 'JobSeq'
							--	,@Action_Type = 'SetCaseNo'
							--	,@Action_Message = @Action_Message
							SELECT @Action_ID = 'JobSeq'
								,@Action_Type = 'SetCaseNo'

							--,@Action_Message = @Cut_Action_Message
							INSERT INTO #SPD_Order_Scheduling_log (
								RID
								,Plan_Date
								,Ori_Plan_Date
								,SpreadMachine_No
								,CutMachine_No
								,Case_Category
								,CaseNo
								,SeqNO
								,MO_NO
								,Spd_Type
								,Table_NO
								,Color_Code
								,Color_Desc
								,SO_No
								,Batch_No
								,Plan_Layer_Qty
								,Act_Layer_Qty
								,pull_date_Min
								,cut_date_Min
								,Plan_Pull_Date_Start
								,Plan_Pull_Date_End
								,Act_Pull_Date_Start
								,Act_Pull_Date_End
								,Plan_Cut_Date_Start
								,Plan_Cut_Date_End
								,Act_Cut_Date_Start
								,Act_Cut_Date_End
								,Used_Length
								,Allocate_Length
								,Input_Length
								,Rest_Minute
								,Cut_SeqNO
								,Can_Cut_Date
								,Can_Spread_Date
								,Create_Date
								,Paper_Sample
								,First_Table
								,QRTYPE
								,QR_Seq
								,Other_Main_Rid
								,IS_Last_Cut
								,Last_Cut_RID
								,Order_Status
								,Order_Status_Type
								,AddStatus
								,AddStatus_Type
								,IS_ALL_Cut
								,Priority_Level
								,Adjust_Machine_No
								,Adjust_Time
								,IS_Old_Table
								,IS_Merge_Cut
								,Merge_Cut_Remark
								,Merge_RID
								,Spread_Scan_Time
								,IsLock
								,Lot_Number_Calculate
								,IsEnough_Material
								,Action_ID
								,Action_Type
								,Action_Date
								,Action_Message
								,Group_Lot_Number
								,Marker_Width
								,Adjust_Start_Time
								,Is_Small_Order
								,Merge_Cut_RID
								,Ori_SpreadMachine_No
								,IsChao
								,Bar_Code
								,Is_Cut
								,Is_Now
								,IsStripe
								,IsPadPrint
								,IsAbnormal
								,Marker_No
								,Group_RID
								,PadPrinting_Together_RID
								)
							SELECT RID
								,Plan_Date
								,Ori_Plan_Date
								,SpreadMachine_No
								,CutMachine_No
								,Case_Category
								,CaseNo
								,SeqNO
								,MO_NO
								,Spd_Type
								,Table_NO
								,Color_Code
								,Color_Desc
								,SO_No
								,Batch_No
								,Plan_Layer_Qty
								,Act_Layer_Qty
								,pull_date_Min
								,cut_date_Min
								,Plan_Pull_Date_Start
								,Plan_Pull_Date_End
								,Act_Pull_Date_Start
								,Act_Pull_Date_End
								,Plan_Cut_Date_Start
								,Plan_Cut_Date_End
								,Act_Cut_Date_Start
								,Act_Cut_Date_End
								,Used_Length
								,Allocate_Length
								,Input_Length
								,Rest_Minute
								,Cut_SeqNO
								,Can_Cut_Date
								,Can_Spread_Date
								,Create_Date
								,Paper_Sample
								,First_Table
								,QRTYPE
								,QR_Seq
								,Other_Main_Rid
								,IS_Last_Cut
								,Last_Cut_RID
								,Order_Status
								,Order_Status_Type
								,AddStatus
								,AddStatus_Type
								,IS_ALL_Cut
								,Priority_Level
								,Adjust_Machine_No
								,Adjust_Time
								,IS_Old_Table
								,IS_Merge_Cut
								,Merge_Cut_Remark
								,Merge_RID
								,Spread_Scan_Time
								,IsLock
								,Lot_Number_Calculate
								,IsEnough_Material
								,Action_ID = @Action_ID
								,Action_Type = @Action_Type
								,Action_Date = GETDATE()
								,Action_Message = @Action_Message
								,Group_Lot_Number
								,Marker_Width
								,Adjust_Start_Time
								,Is_Small_Order
								,Merge_Cut_RID
								,Ori_SpreadMachine_No = SpreadMachine_No
								,IsChao
								,Bar_Code
								,Is_Cut
								,Is_Now
								,IsStripe
								,IsPadPrint
								,IsAbnormal
								,Marker_No
								,Group_RID
								,PadPrinting_Together_RID
							FROM #SPD_Order_Scheduling_idx
							WHERE RID = @RID
						END
					END
					ELSE
					BEGIN
						--重新找到最后的拉布机
						SELECT @LastCut_SpreadMachine_No = ''
							,@LastCut_CutMachine_No = ''
							,@RID_26 = ''

						SELECT TOP 1 @LastCut_SpreadMachine_No = SpreadMachine_No
							,@LastCut_CutMachine_No = CutMachine_No
							--,@Plan_Pull_Date_Start = Plan_Pull_Date_End
							,@RID_26 = S.RID
						FROM #SPD_Order_Scheduling_idx S
						INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.MST_RID = @RID
							AND M.DTL_RID = S.RID
						--INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M2.Data_Type
						--	AND M2.MST_RID = M.MST_RID
						--	AND M2.DTL_RID = S.RID
						WHERE M.Data_Type = 'MergeCut'
							AND S.Plan_Pull_Date_Start IS NOT NULL
						ORDER BY S.Plan_Pull_Date_End DESC

						IF ISNULL(@LastCut_SpreadMachine_No, '') <> ''
						BEGIN
							SELECT @SpreadMachine_No = @LastCut_SpreadMachine_No
								,@CutMachine_No = @LastCut_CutMachine_No
						END

						--UPDATE S
						--SET SpreadMachine_No = @LastCut_SpreadMachine_No
						--	,CutMachine_No = @LastCut_CutMachine_No
						--	,S.Is_Now = 1
						--FROM #SPD_Order_Scheduling_idx S
						--INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
						--	AND M.MST_RID = S.RID
						--WHERE Data_Type = 'MergeCut'
						SELECT @RID_25 = ''

						--SELECT TOP 1 @RID_25 = RID
						--FROM #SPD_Order_Scheduling_idx S
						--WHERE @LastCut_SpreadMachine_No = SpreadMachine_No
						--	AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
						--	AND Plan_Date = @Spread_Plan_Date
						--ORDER BY Plan_Pull_Date_Start DESC
						--SELECT @JsonStr = ''
						--SELECT @JsonStr = (
						--		SELECT S.*
						--		FROM #SPD_Order_Scheduling_idx S
						--		INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = S.RID
						--			AND M.MST_RID = @RID
						--		WHERE Data_Type = 'MergeCut'
						--		FOR JSON PATH
						--		)
						SELECT @Action_Message = N'合拉锁定在@RID_26=' + ISNULL(@RID_26, '') + N'后面,原后面存在@RID_25=' + ISNULL(@RID_25, '')

						--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
						--	,@Action_ID = 'JobSeq'
						--	,@Action_Type = 'MergeCutLock1'
						--	,@Action_Message = @Action_Message
						SELECT @Action_ID = 'JobSeq'
							,@Action_Type = 'MergeCutLock1'

						--,@Action_Message = @Cut_Action_Message
						INSERT INTO #SPD_Order_Scheduling_log (
							RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID
							,Action_Type
							,Action_Date
							,Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
							)
						SELECT S.RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,S.Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID = @Action_ID
							,Action_Type = @Action_Type
							,Action_Date = GETDATE()
							,Action_Message = @Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No = SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
						FROM #SPD_Order_Scheduling_idx S
						INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = S.RID
							AND M.MST_RID = @RID
						WHERE Data_Type = 'MergeCut'
					END
							--ELSE
				END

				IF ISNULL(@IS_Last_Cut, 0) = 1
					AND ISNULL(@RID, '') <> ''
					AND isnull(@Order_Status_Type, 99) > 1
				BEGIN
					--UPDATE S
					--SET S.Last_Cut_rid = @RID
					--FROM #SPD_Order_Scheduling_idx S
					--WHERE Batch_No = @Batch_No
					--	AND SO_NO = @SO_NO
					--	AND ISNULL(IS_Last_Cut, 0) = 0
					--	AND RID <> @RID
					--	AND Order_Status_Type >= 1
					--	AND Ori_Plan_Date = @Ori_Plan_Date
					--UPDATE S
					--SET S.Last_Cut_rid = @RID
					--FROM #SPD_Order_Scheduling_idx S
					--WHERE RID = @RID
					UPDATE S
					SET S.Last_Cut_rid = @RID
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON Data_Type = 'LastCut'
						AND M.Dtl_RID = S.RID
						AND M.MST_RID = @RID --CONVERT(VARCHAR(20), S.TABLE_NO) = M.TABLE_NO

					UPDATE S
					SET S.Last_Cut_rid = @RID
					FROM #SPD_Order_Scheduling_idx S
					WHERE RID = @RID

					IF object_id('tempdb..#SPD_Order_Scheduling_LastCut') IS NOT NULL
						DROP TABLE #SPD_Order_Scheduling_LastCut

					SELECT TOP 1 *
					INTO #SPD_Order_Scheduling_LastCut
					FROM #SPD_Order_Scheduling_idx S
					WHERE Last_Cut_rid = @RID
						AND RID <> @RID
						AND Plan_Pull_Date_Start IS NULL
						AND Order_Status_Type >= 1
					ORDER BY ISNULL(S.Is_Now, 0) DESC
						,CASE 
							WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
								THEN 0
							ELSE 1
							END
						,isnull(Order_Status_Type, 99)
						,CASE 
							WHEN isnull(Order_Status_Type, 99) = 2
								THEN S.SeqNO
							ELSE 999
							END
						,PLAN_DATE
						,[IsEnough_Material] DESC
						,CASE 
							WHEN isnull(Paper_Sample, '') <> ''
								THEN 0
							ELSE 1
							END
						,CASE 
							WHEN isnull(Bar_Code, '') <> ''
								THEN 0
							ELSE 1
							END
						,[Priority_Level]
						--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
						,ISNULL(IS_Last_Cut, 0)

					IF EXISTS (
							SELECT TOP 1 1
							FROM #SPD_Order_Scheduling_LastCut
							)
					BEGIN
						SELECT TOP 1 @RID = RID
							,@Adjust_Machine_No = Adjust_Machine_No
							,@SO_No = SO_No
							,@Batch_No = Batch_No
							,@Spread_Plan_Date = Plan_Date
							--,@Marker_Width = ISNULL(Marker_Width, 0)
							--,@Is_Small_Order = ISNULL(Is_Small_Order, 0)
							,@CutMachine_No = CutMachine_No
							,@IS_Last_Cut = IS_Last_Cut
							,@IS_Merge_Cut = IS_Merge_Cut
							,@Ori_Plan_Date = Ori_Plan_Date
							,@MO_NO = MO_NO
							,@Merge_Cut_Remark = Merge_Cut_Remark
							,@Assigned_SpreadMachine_No = SpreadMachine_No
							,@Table_No = Table_No
							,@Spd_Type = Spd_Type
							,@Order_Status_Type = Order_Status_Type
							,@Cut_date_Min = cut_date_Min
						FROM #SPD_Order_Scheduling_LastCut

						IF @RID <> ''
						BEGIN
							UPDATE S
							SET S.CaseNo = 10
							FROM #SPD_Order_Scheduling_idx S
							WHERE S.RID = @RID

							--SELECT @JsonStr = ''
							--SELECT @JsonStr = (
							--		SELECT S.*
							--		FROM #SPD_Order_Scheduling_idx S
							--		WHERE rid = @RID
							--		FOR JSON PATH
							--		)
							SELECT @Action_Message = N'确定顺序位置'

							--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
							--	,@Action_ID = 'JobSeq'
							--	,@Action_Type = 'SetCaseNo'
							--	,@Action_Message = @Action_Message
							SELECT @Action_ID = 'JobSeq'
								,@Action_Type = 'SetCaseNo'

							--,@Action_Message = @Cut_Action_Message
							INSERT INTO #SPD_Order_Scheduling_log (
								RID
								,Plan_Date
								,Ori_Plan_Date
								,SpreadMachine_No
								,CutMachine_No
								,Case_Category
								,CaseNo
								,SeqNO
								,MO_NO
								,Spd_Type
								,Table_NO
								,Color_Code
								,Color_Desc
								,SO_No
								,Batch_No
								,Plan_Layer_Qty
								,Act_Layer_Qty
								,pull_date_Min
								,cut_date_Min
								,Plan_Pull_Date_Start
								,Plan_Pull_Date_End
								,Act_Pull_Date_Start
								,Act_Pull_Date_End
								,Plan_Cut_Date_Start
								,Plan_Cut_Date_End
								,Act_Cut_Date_Start
								,Act_Cut_Date_End
								,Used_Length
								,Allocate_Length
								,Input_Length
								,Rest_Minute
								,Cut_SeqNO
								,Can_Cut_Date
								,Can_Spread_Date
								,Create_Date
								,Paper_Sample
								,First_Table
								,QRTYPE
								,QR_Seq
								,Other_Main_Rid
								,IS_Last_Cut
								,Last_Cut_RID
								,Order_Status
								,Order_Status_Type
								,AddStatus
								,AddStatus_Type
								,IS_ALL_Cut
								,Priority_Level
								,Adjust_Machine_No
								,Adjust_Time
								,IS_Old_Table
								,IS_Merge_Cut
								,Merge_Cut_Remark
								,Merge_RID
								,Spread_Scan_Time
								,IsLock
								,Lot_Number_Calculate
								,IsEnough_Material
								,Action_ID
								,Action_Type
								,Action_Date
								,Action_Message
								,Group_Lot_Number
								,Marker_Width
								,Adjust_Start_Time
								,Is_Small_Order
								,Merge_Cut_RID
								,Ori_SpreadMachine_No
								,IsChao
								,Bar_Code
								,Is_Cut
								,Is_Now
								,IsStripe
								,IsPadPrint
								,IsAbnormal
								,Marker_No
								,Group_RID
								,PadPrinting_Together_RID
								)
							SELECT RID
								,Plan_Date
								,Ori_Plan_Date
								,SpreadMachine_No
								,CutMachine_No
								,Case_Category
								,CaseNo
								,SeqNO
								,MO_NO
								,Spd_Type
								,Table_NO
								,Color_Code
								,Color_Desc
								,SO_No
								,Batch_No
								,Plan_Layer_Qty
								,Act_Layer_Qty
								,pull_date_Min
								,cut_date_Min
								,Plan_Pull_Date_Start
								,Plan_Pull_Date_End
								,Act_Pull_Date_Start
								,Act_Pull_Date_End
								,Plan_Cut_Date_Start
								,Plan_Cut_Date_End
								,Act_Cut_Date_Start
								,Act_Cut_Date_End
								,Used_Length
								,Allocate_Length
								,Input_Length
								,Rest_Minute
								,Cut_SeqNO
								,Can_Cut_Date
								,Can_Spread_Date
								,Create_Date
								,Paper_Sample
								,First_Table
								,QRTYPE
								,QR_Seq
								,Other_Main_Rid
								,IS_Last_Cut
								,Last_Cut_RID
								,Order_Status
								,Order_Status_Type
								,AddStatus
								,AddStatus_Type
								,IS_ALL_Cut
								,Priority_Level
								,Adjust_Machine_No
								,Adjust_Time
								,IS_Old_Table
								,IS_Merge_Cut
								,Merge_Cut_Remark
								,Merge_RID
								,Spread_Scan_Time
								,IsLock
								,Lot_Number_Calculate
								,IsEnough_Material
								,Action_ID = @Action_ID
								,Action_Type = @Action_Type
								,Action_Date = GETDATE()
								,Action_Message = @Action_Message
								,Group_Lot_Number
								,Marker_Width
								,Adjust_Start_Time
								,Is_Small_Order
								,Merge_Cut_RID
								,Ori_SpreadMachine_No = SpreadMachine_No
								,IsChao
								,Bar_Code
								,Is_Cut
								,Is_Now
								,IsStripe
								,IsPadPrint
								,IsAbnormal
								,Marker_No
								,Group_RID
								,PadPrinting_Together_RID
							FROM #SPD_Order_Scheduling_idx
							WHERE RID = @RID
						END
					END
					ELSE
					BEGIN
						--重新找到最后的拉布机
						SELECT @LastCut_SpreadMachine_No = ''
							,@LastCut_CutMachine_No = ''
							--,@Plan_Pull_Date_Start = NULL
							,@RID_26 = ''

						SELECT TOP 1 @LastCut_SpreadMachine_No = SpreadMachine_No
							,@LastCut_CutMachine_No = CutMachine_No
							--,@Plan_Pull_Date_Start = Plan_Pull_Date_End
							,@RID_26 = S.RID
						FROM #SPD_Order_Scheduling_idx S
						INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.MST_RID = @RID
							AND M.DTL_RID = S.RID
						--INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M.Data_Type
						--	AND M2.MST_RID = M.MST_RID
						--	AND M2.DTL_RID = S.RID
						WHERE M.Data_Type = 'LastCut'
							AND S.Plan_Pull_Date_Start IS NOT NULL
						ORDER BY S.Plan_Pull_Date_End DESC

						IF ISNULL(@LastCut_SpreadMachine_No, '') <> ''
						BEGIN
							SELECT @SpreadMachine_No = @LastCut_SpreadMachine_No
								,@CutMachine_No = @LastCut_CutMachine_No
						END

						--UPDATE S
						--SET SpreadMachine_No = @LastCut_SpreadMachine_No
						--	,CutMachine_No = @LastCut_CutMachine_No
						--	,S.Is_Now = 1
						--FROM #SPD_Order_Scheduling_idx S
						--INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
						--	AND M.MST_RID = S.RID
						--WHERE Data_Type = 'LastCut'
						--UPDATE S
						--SET S.Plan_Pull_Date_Start = NULL
						--	,S.Plan_Pull_Date_End = NULL
						SELECT @RID_25 = ''

						--SELECT TOP 1 @RID_25 = RID
						--FROM #SPD_Order_Scheduling_idx S
						--WHERE @LastCut_SpreadMachine_No = SpreadMachine_No
						--	AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
						--	AND Plan_Date = @Spread_Plan_Date
						--ORDER BY Plan_Pull_Date_Start DESC
						--SELECT @JsonStr = ''
						--SELECT @JsonStr = (
						--		SELECT S.*
						--		FROM #SPD_Order_Scheduling_idx S
						--		INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = S.RID
						--			AND M.MST_RID = @RID
						--		WHERE Data_Type = 'LastCut'
						--		FOR JSON PATH
						--		)
						SELECT @Action_Message = N'后拉锁定在@RID_26=' + ISNULL(@RID_26, '') + N'后面,原后面存在@RID_25=' + ISNULL(@RID_25, '')

						--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
						--	,@Action_ID = 'JobSeq'
						--	,@Action_Type = 'LastCutLock1'
						--	,@Action_Message = @Action_Message
						SELECT @Action_ID = 'JobSeq'
							,@Action_Type = 'LastCutLock1'

						--,@Action_Message = @Cut_Action_Message
						INSERT INTO #SPD_Order_Scheduling_log (
							RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID
							,Action_Type
							,Action_Date
							,Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
							)
						SELECT S.RID
							,Plan_Date
							,Ori_Plan_Date
							,SpreadMachine_No
							,CutMachine_No
							,Case_Category
							,CaseNo
							,SeqNO
							,MO_NO
							,Spd_Type
							,Table_NO
							,Color_Code
							,Color_Desc
							,SO_No
							,Batch_No
							,Plan_Layer_Qty
							,Act_Layer_Qty
							,pull_date_Min
							,cut_date_Min
							,Plan_Pull_Date_Start
							,Plan_Pull_Date_End
							,Act_Pull_Date_Start
							,Act_Pull_Date_End
							,Plan_Cut_Date_Start
							,Plan_Cut_Date_End
							,Act_Cut_Date_Start
							,Act_Cut_Date_End
							,Used_Length
							,Allocate_Length
							,Input_Length
							,Rest_Minute
							,Cut_SeqNO
							,Can_Cut_Date
							,Can_Spread_Date
							,S.Create_Date
							,Paper_Sample
							,First_Table
							,QRTYPE
							,QR_Seq
							,Other_Main_Rid
							,IS_Last_Cut
							,Last_Cut_RID
							,Order_Status
							,Order_Status_Type
							,AddStatus
							,AddStatus_Type
							,IS_ALL_Cut
							,Priority_Level
							,Adjust_Machine_No
							,Adjust_Time
							,IS_Old_Table
							,IS_Merge_Cut
							,Merge_Cut_Remark
							,Merge_RID
							,Spread_Scan_Time
							,IsLock
							,Lot_Number_Calculate
							,IsEnough_Material
							,Action_ID = @Action_ID
							,Action_Type = @Action_Type
							,Action_Date = GETDATE()
							,Action_Message = @Action_Message
							,Group_Lot_Number
							,Marker_Width
							,Adjust_Start_Time
							,Is_Small_Order
							,Merge_Cut_RID
							,Ori_SpreadMachine_No = SpreadMachine_No
							,IsChao
							,Bar_Code
							,Is_Cut
							,Is_Now
							,IsStripe
							,IsPadPrint
							,IsAbnormal
							,Marker_No
							,Group_RID
							,PadPrinting_Together_RID
						FROM #SPD_Order_Scheduling_idx S
						INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = S.RID
							AND M.MST_RID = @RID
						WHERE Data_Type = 'LastCut'
					END
				END
			END

			IF ISNULL(@RID, '') = ''
				--AND NOT EXISTS (
				--	SELECT TOP 1 1
				--	FROM #SPD_Order_Scheduling_idx
				--	WHERE ISNULL(SpreadMachine_No, '') = ''
				--		OR Plan_Pull_Date_Start IS NULL
				--	)
			BEGIN
				DECLARE @BreakMessage NVARCHAR(MAX) = N'没找到床次:@SpreadMachine_No=' + ISNULL(@SpreadMachine_No, '') + ',@CutMachine_No=' + ISNULL(@CutMachine_No, '') + ',@RID=' + ISNULL(@RID, '') + ',@Ori_SPD_RID=' + ISNULL(@Ori_SPD_RID, '')

				PRINT @BreakMessage

				INSERT INTO LOGS (
					RID
					,UserID
					,ActionTime
					,FullURL
					,Source
					,StackTrace
					,Message
					,LogType
					)
				SELECT RID = CONVERT(VARCHAR(50), NEWID())
					,UserID = ''
					,ActionTime = GETDATE()
					,FullURL = 'BreakMessage'
					,Source = 'P_Task_Calculate'
					,StackTrace = @Calculate_LotNumber
					,Message = @BreakMessage
					,LogType = convert(VARCHAR(50), @Quit_Index)

				IF ISNULL(@Ori_SPD_RID, '') = ''
				BEGIN
					BREAK;
				END
			END

			IF @IsDebug = 1
			BEGIN
				SELECT #pull_date_Min2 = ''
					,Spread_Plan_Date = @Spread_Plan_Date
					,Current_SpreadMachine_No = @SpreadMachine_No
					,*
					,CurrentDate = @CurrentDate
					,RID = @RID
					,MO_No = @MO_No
					,Table_No = @Table_No
					,Spd_Type = @Spd_Type
					,Assigned_SpreadMachine_No = @Assigned_SpreadMachine_No
				FROM #pull_date_Min
			END

			IF object_id('tempdb..#TB_SpreadMachine_Adjust') IS NOT NULL
				DROP TABLE #TB_SpreadMachine_Adjust

			SELECT DISTINCT S.SpreadMachine_No
			INTO #TB_SpreadMachine_Adjust
			FROM #TB_Calculate_Inserting_Info S
			INNER JOIN #TB_SpreadMachine M ON M.SpreadMachine_No = S.SpreadMachine_No
				AND ISNULL(M.Valid_Status, 0) = 1
			WHERE MO_NO = @MO_No
				AND TABLE_NO = @Table_No
				AND SPD_Type = @Spd_Type

			IF ISNULL(@Order_Status_Type, 99) >= 2 --处理插单
				AND EXISTS (
					SELECT TOP 1 1
					FROM #TB_SpreadMachine_Adjust
					)
				AND @Assigned_SpreadMachine_No NOT IN ('Fry')
			BEGIN
				SELECT @SpreadMachine_No_Adjust = ''

				IF object_id('tempdb..#pull_date_Min_Adjust') IS NOT NULL
					DROP TABLE #pull_date_Min_Adjust

				--PRINT '2157:@CutMachine_No=' + isnull(@CutMachine_No, 0)
				SELECT SpreadMachine_No = ISNULL(A.SpreadMachine_No, '')
					,pull_date_Min = SUM(isnull(pull_date_Min, 0))
				INTO #pull_date_Min_Adjust
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN #TB_SpreadMachine_Adjust A ON A.SpreadMachine_No = S.SpreadMachine_No
				WHERE ISNULL(A.SpreadMachine_No, '') <> ''
					AND ISNULL(Order_Status_Type, 0) > 0
				--AND Plan_Pull_Date_Start IS NOT NULL
				GROUP BY ISNULL(A.SpreadMachine_No, '')

				INSERT INTO #pull_date_Min (
					SpreadMachine_No
					,pull_date_Min
					)
				SELECT DISTINCT M.SpreadMachine_No
					,pull_date_Min = 0
				FROM #TB_SpreadMachine_Adjust M --WITH (NOLOCK)
				LEFT JOIN #pull_date_Min_Adjust C ON M.SpreadMachine_No = C.SpreadMachine_No
				--AND ISNULL(M.Valid_Status, 0) = 1
				WHERE C.SpreadMachine_No IS NULL

				--AND isnull(M.CutMachine_No, '') = @CutMachine_No
				--AND ISNULL(M.Valid_Status, 0) = 1
				DELETE
				FROM #pull_date_Min_Adjust
				WHERE SpreadMachine_No NOT IN (
						SELECT SpreadMachine_No
						FROM #TB_SpreadMachine M -- WITH (NOLOCK)
						WHERE ISNULL(M.Valid_Status, 0) = 1
						)

				SELECT TOP 1 @SpreadMachine_No_Adjust = P.SpreadMachine_No
				FROM #pull_date_Min_Adjust p
				INNER JOIN #TB_SpreadMachine S ON P.SpreadMachine_No = S.SpreadMachine_No
				ORDER BY pull_date_Min

				IF ISNULL(@SpreadMachine_No_Adjust, '') <> ''
				BEGIN
					SELECT @SpreadMachine_No = @SpreadMachine_No_Adjust
						,@Assigned_SpreadMachine_No = @SpreadMachine_No_Adjust

					--UPDATE S
					--SET Adjust_Machine_No = @SpreadMachine_No_Adjust
					--,Adjust_Time = Limit_Completed_Time
					--,Adjust_Start_Time = Limit_Start_Time
					--FROM #SPD_Order_Scheduling_idx S 
					--INNER JOIN 
					--WHERE RID = @RID
					UPDATE S
					SET S.Adjust_Machine_No = I.SpreadMachine_No
						,Adjust_Time = Limit_Completed_Time
						,Adjust_Start_Time = Limit_Start_Time
						,S.CutMachine_No = M.CutMachine_No
						,Order_Status_Type = CASE 
							WHEN Limit_Completed_Time <= dbo.fn_CCT_GetEndTimeNew(dateadd(SECOND, pull_date_Min * 60.00, ISNULL(GETDATE(), GETDATE())),pull_date_Min)
								THEN 3
							ELSE NULL
							END
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN #TB_Calculate_Inserting_Info I ON S.MO_NO = I.MO_NO
						AND S.Table_No = I.Table_No
						AND S.Spd_Type = I.Spd_Type
						AND I.SpreadMachine_No = @SpreadMachine_No_Adjust
					INNER JOIN #TB_SpreadMachine M WITH (NOLOCK) ON M.SpreadMachine_No = S.SpreadMachine_No
					WHERE S.RID = @RID
				END
			END

			IF ISNULL(@Assigned_SpreadMachine_No, '') <> '' --判断是否已分配
			BEGIN
				SELECT @SpreadMachine_No = @Assigned_SpreadMachine_No
			END

			IF ISNULL(@SpreadMachine_No, '') = ''
			BEGIN
				SELECT TOP 1 @SpreadMachine_No = 'TBD'
			END

			SELECT @CutMachine_No_Current = @CutMachine_No

			--SELECT @CutMachine_No_Current = CutMachine_NO
			--FROM #TB_SpreadMachine --WITH (NOLOCK)
			--WHERE SpreadMachine_No = @SpreadMachine_No
			SELECT TOP 1 @CutMachine_No_Current = CutMachine_No FROM (
			SELECT CutMachine_No,Plan_Cut_Date_End = MAX(Plan_Cut_Date_End) FROM #SPD_Order_Scheduling_idx WHERE CutMachine_No IN( 
			SELECT DISTINCT CutMachine_No FROM [dbo].[V_MES_CuttingMachineMap] WHERE SpreadMachine_No=@SpreadMachine_No
			) GROUP BY  CutMachine_No--ORDER BY Plan_Cut_Date_End DESC
			) S ORDER BY S.Plan_Cut_Date_End

			IF ISNULL(@CutMachine_No_Current,'')=''
			BEGIN
				SELECT @CutMachine_No_Current = CutMachine_NO
				FROM #TB_SpreadMachine --WITH (NOLOCK)
				WHERE SpreadMachine_No = @SpreadMachine_No
			END

			IF @SpreadMachine_No = 'TBD'
			BEGIN
				SELECT @CutMachine_No_Current = 'TBD'
			END

			SELECT @SpreadSeqNO = ISNULL(MAX(SeqNO), 0)
			FROM #SPD_Order_Scheduling_idx
			WHERE SpreadMachine_No = @SpreadMachine_No

			SELECT @SpreadSeqNO = @SpreadSeqNO + 1
				,@Cut_Seqno = 1

			SELECT @Cut_Seqno = ISNULL(MAX(Cut_Seqno), 0)
			FROM #SPD_Order_Scheduling_idx
			WHERE CutMachine_No = @CutMachine_No_Current

			SELECT @Cut_Seqno = @Cut_Seqno + 1

			UPDATE #SPD_Order_Scheduling_idx
			SET SpreadMachine_No = @SpreadMachine_No
				,SeqNO = @SpreadSeqNO
				,Cut_Seqno = @Cut_Seqno
				,CutMachine_No = @CutMachine_No_Current
			WHERE RID = @RID

			--SELECT @JsonStr = ''
			--SELECT @JsonStr = (
			--		SELECT TOP 1 *
			--		FROM #SPD_Order_Scheduling_idx
			--		WHERE RID = @RID
			--		FOR JSON PATH
			--		)
			--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
			--	,@Action_ID = 'JobSeq'
			--	,@Action_Type = 'AllocatedSPD'
			--	,@Action_Message = N'初步分配拉布机'
			SELECT @Action_ID = 'JobSeq'
				,@Action_Type = 'AllocatedSPD'
				,@Action_Message = N'初步分配拉布机'

			INSERT INTO #SPD_Order_Scheduling_log (
				RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID
				,Action_Type
				,Action_Date
				,Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
				)
			SELECT RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID = @Action_ID
				,Action_Type = @Action_Type
				,Action_Date = GETDATE()
				,Action_Message = @Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No = SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
			FROM #SPD_Order_Scheduling_idx
			WHERE RID = @RID

			SELECT @CutMachine_No = ''
				,@SpreadMachine_No = ''
				,@SO_No = ''
				,@MO_No = ''
				,@Batch_No = ''
				,@Spread_Scan_Time = NULL
				,@Cut_SeqNO = 1
				,@SeqNO = 1
				,@Plan_Pull_Date_End = NULL
				,@Plan_Pull_Date_Start = NULL
				,@pull_date_Min = 10.00
				,@IS_Last_Cut = 0
				,@Plan_Pull_Date_Start_Last = NULL
				,@Spread_Plan_Date = NULL
				,@Order_Status_Type = 0
				,@IS_Merge_Cut = 0
				,@Merge_Cut_Remark = ''
				,@Adjust_Machine_No = ''
				,@Ori_RID = ''
				,@Step = ''
				,@Ori_Plan_Date = NULL
				,@Cut_date_Min = 0

			SELECT TOP 1 @CutMachine_No = CutMachine_No
				,@SpreadMachine_No = SpreadMachine_No
				,@SO_No = SO_No
				,@MO_No = MO_No
				,@Batch_No = Batch_No
				,@Spread_Scan_Time = Spread_Scan_Time
				,@Cut_SeqNO = Cut_SeqNO
				,@SeqNO = SeqNO
				,@pull_date_Min = pull_date_Min
				,@IS_Last_Cut = IS_Last_Cut
				,@Spread_Plan_Date = Plan_Date
				,@Order_Status_Type = Order_Status_Type
				,@IS_Merge_Cut = IS_Merge_Cut
				,@Merge_Cut_Remark = Merge_Cut_Remark
				,@Adjust_Machine_No = Adjust_Machine_No
				,@Ori_Plan_Date = Ori_Plan_Date
				,@Cut_date_Min = cut_date_Min
			FROM #SPD_Order_Scheduling_idx
			WHERE Plan_Pull_Date_Start IS NULL
				AND Order_Status_Type > 0
				AND RID = @RID

			--判断是不是首床
			IF NOT EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx
					WHERE SpreadMachine_No = @SpreadMachine_No
						AND Plan_Date <= @Work_Date
						AND isnull(Order_Status_Type, 0) > 0
						AND Plan_Pull_Date_End IS NOT NULL
					)
				AND @Spread_Plan_Date <= @Work_Date
			BEGIN
				SELECT @Plan_Pull_Date_Start = [dbo].[fn_CCT_GetStartTime](getdate())

				SELECT @Step = @Step + ';SPD1=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')

				IF @Spread_Scan_Time IS NOT NULL
					AND @Spread_Scan_Time < @Plan_Pull_Date_Start
				BEGIN
					SELECT TOP 1 @Plan_Pull_Date_Start_Last = Plan_Pull_Date_End --ISNULL(MAX(Plan_Pull_Date_End), GETDATE())
					FROM #SPD_Order_Scheduling_idx
					WHERE SpreadMachine_No = @SpreadMachine_No
						AND Plan_Pull_Date_End IS NOT NULL
						AND Plan_Date = @Spread_Plan_Date
					ORDER BY Plan_Pull_Date_End DESC

					SELECT @Plan_Pull_Date_Start = CASE 
							WHEN @Plan_Pull_Date_Start_Last IS NOT NULL
								AND @Plan_Pull_Date_Start_Last > @Spread_Scan_Time
								--AND @Plan_Pull_Date_Start_Last < GETDATE()
								THEN @Plan_Pull_Date_Start_Last
							ELSE @Spread_Scan_Time
							END

					SELECT @Step = @Step + ';SPD2=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')

					SELECT @Plan_Pull_Date_Start_Last = NULL
				END
			END
			ELSE
			BEGIN
				IF ISNULL(@Order_Status_Type, 0) = 1
					AND @Spread_Scan_Time IS NOT NULL
				BEGIN
					SELECT @Plan_Pull_Date_Start = @Spread_Scan_Time

					SELECT @Step = @Step + ';SPD3.1=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')
				END
				ELSE
				BEGIN
					IF ISNULL(@Order_Status_Type, 0) = 3
						--AND @Adjust_Time IS NOT NULL
					BEGIN
						--SELECT @Plan_Pull_Date_Start = @Adjust_Time
						SELECT TOP 1 @Plan_Pull_Date_Start = Plan_Pull_Date_End --ISNULL(MAX(Plan_Pull_Date_End), GETDATE())
						FROM #SPD_Order_Scheduling_idx
						WHERE SpreadMachine_No = @SpreadMachine_No
							AND Plan_Pull_Date_End IS NOT NULL
						--AND Plan_Pull_Date_End <= @Adjust_Time
						--AND Plan_Date = @Spread_Plan_Date
						--AND 1 = CASE 
						--	WHEN (
						--			@Work_Date < @Spread_Plan_Date
						--			AND isnull(Order_Status_Type, 0) > 2
						--			)
						--		OR Plan_Date <= @Work_Date
						--		THEN 1
						--	ELSE 0
						--	END
						ORDER BY Plan_Pull_Date_End DESC

						SELECT @Step = @Step + ';SPD3.2=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')
					END

					IF @Plan_Pull_Date_Start IS NULL
					BEGIN
						SELECT TOP 1 @Plan_Pull_Date_Start = Plan_Pull_Date_End --ISNULL(MAX(Plan_Pull_Date_End), GETDATE())
						FROM #SPD_Order_Scheduling_idx
						WHERE SpreadMachine_No = @SpreadMachine_No
							AND Plan_Pull_Date_End IS NOT NULL
							AND Plan_Date = @Spread_Plan_Date
							AND 1 = CASE 
								WHEN (
										@Work_Date < @Spread_Plan_Date
										AND isnull(Order_Status_Type, 0) > 2
										)
									OR Plan_Date <= @Work_Date
									THEN 1
								ELSE 0
								END
						ORDER BY Plan_Pull_Date_End DESC

						SELECT @Step = @Step + ';SPD3.3=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')
					END
				END

				SELECT @Step = @Step + ';SPD3=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')

				IF @Plan_Pull_Date_Start < GETDATE()
					AND @Work_Date = @Spread_Plan_Date
				BEGIN
					SELECT @Plan_Pull_Date_Start = [dbo].[fn_CCT_GetStartTime](getdate())

					SELECT @Step = @Step + ';SPD4=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')
				END

				IF @Plan_Pull_Date_Start IS NULL
					AND @Work_Date < @Spread_Plan_Date
				BEGIN
					SELECT @Plan_Pull_Date_Start = dateadd(day, datediff(day, @Work_Date, @Spread_Plan_Date), MIN(Start_Time))
					FROM TB_Calculate_Shift

					SELECT @Step = @Step + ';SPD5=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')
				END
						--SELECT @Plan_Pull_Date_Start = ISNULL(@Plan_Pull_Date_Start, GETDATE())
						--SELECT @Plan_Pull_Date_End = [dbo].[fn_CCT_GetEndTime](dateadd(SECOND, @pull_date_Min * 60.00, ISNULL(@Plan_Pull_Date_Start, GETDATE())))
			END

			IF @Plan_Pull_Date_Start IS NULL
			BEGIN
				SELECT @Plan_Pull_Date_Start = [dbo].[fn_CCT_GetStartTime](getdate()) --ISNULL(@Plan_Pull_Date_Start, [dbo].[fn_CCT_GetStartTime](getdate()))

				SELECT @Step = @Step + ';SPD7=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')
			END

			SELECT TOP 1 @Plan_Pull_Date_Start_Last = Plan_Pull_Date_End --ISNULL(MAX(Plan_Pull_Date_End), GETDATE())
			FROM #SPD_Order_Scheduling_idx
			WHERE SpreadMachine_No = @SpreadMachine_No
				AND Plan_Pull_Date_End IS NOT NULL
				AND Plan_Date = @Spread_Plan_Date
			ORDER BY Plan_Pull_Date_End DESC

			IF @Plan_Pull_Date_Start_Last IS NOT NULL
				AND @Plan_Pull_Date_Start_Last > @Plan_Pull_Date_Start
			BEGIN
				SELECT @Plan_Pull_Date_Start = @Plan_Pull_Date_Start_Last

				SELECT @Step = @Step + ';SPD8=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')
			END

			--判断当前床是否已经有两床不能再铺 Damon gu 2025/04/11
			IF @Order_Status_Type > 1
			BEGIN
				SELECT @Current_PutTableQty = 0

				SELECT @Current_PutTableQty = COUNT(1)
				FROM #SPD_Order_Scheduling_idx
				WHERE SpreadMachine_No = @SpreadMachine_No
					AND ISNULL(IS_CUT, 0) = 0
					AND Plan_Cut_Date_End >= @Plan_Pull_Date_Start

				SELECT @PutTableQty_Quit_Index = 1

				--直到只有两床
				WHILE @Current_PutTableQty >= @LineBalance_SpreadMachine_PutTableQty
					AND @PutTableQty_Quit_Index <= 2000
				BEGIN
					SELECT @PutTableQty_Quit_Index = @PutTableQty_Quit_Index + 1

					SELECT TOP 1 @Plan_Pull_Date_Start = Plan_Cut_Date_End
					FROM #SPD_Order_Scheduling_idx
					WHERE SpreadMachine_No = @SpreadMachine_No
						AND ISNULL(IS_CUT, 0) = 0
						AND Plan_Cut_Date_End >= @Plan_Pull_Date_Start
					ORDER BY Plan_Cut_Date_End

					SELECT @Step = @Step + ';SPD9=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')

					SELECT @Current_PutTableQty = 0

					SELECT @Current_PutTableQty = COUNT(1)
					FROM #SPD_Order_Scheduling_idx
					WHERE SpreadMachine_No = @SpreadMachine_No
						AND ISNULL(IS_CUT, 0) = 0
						AND Plan_Cut_Date_End >= @Plan_Pull_Date_Start
						--SELECT @Plan_Pull_Date_Start = Plan_Cut_Date_End
						--FROM #SPD_Order_Scheduling_idx
						--WHERE SpreadMachine_No = @SpreadMachine_No
						--	AND ISNULL(IS_CUT, 0) = 0
						--	AND Plan_Cut_Date_End >= @Plan_Pull_Date_Start
						--ORDER BY Plan_Cut_Date_End
				END
			END

			SELECT @Plan_Pull_Date_End = [dbo].[fn_CCT_GetEndTimeNew](dateadd(SECOND, @pull_date_Min * 60.00, ISNULL(@Plan_Pull_Date_Start, GETDATE())),@pull_date_Min)

			IF @Plan_Pull_Date_End <= GETDATE()
			BEGIN
				SELECT @Plan_Pull_Date_End = [dbo].[fn_CCT_GetEndTimeNew](GETDATE(),@pull_date_Min)
			END

			--计算裁剪时间 Damon gu 2025/04/11
			SELECT @Plan_Cut_Date_End = NULL
				,@Plan_Cut_Date_Start = NULL

			SELECT TOP 1 @Plan_Cut_Date_Start = Plan_Cut_Date_End
			FROM #SPD_Order_Scheduling_idx t
			WHERE CutMachine_No = @CutMachine_No
				AND Plan_Cut_Date_End >= @Plan_Pull_Date_End
				AND Plan_Date <= @Spread_Plan_Date
			ORDER BY Plan_Cut_Date_End DESC

			IF @Plan_Cut_Date_Start IS NULL
			BEGIN
				SELECT @Plan_Cut_Date_Start = @Plan_Pull_Date_End
			END

			SELECT @Plan_Cut_Date_End = [dbo].[fn_CCT_GetEndTimeNew](dateadd(SECOND, @Cut_date_Min * 60.00, ISNULL(@Plan_Cut_Date_Start, GETDATE())),@Cut_date_Min)

			IF @Plan_Cut_Date_End <= GETDATE()
			BEGIN
				SELECT @Plan_Cut_Date_End = [dbo].[fn_CCT_GetEndTimeNew](GETDATE(),@Cut_date_Min)
			END

			SELECT @Step = @Step + ';SPD10=' + ISNULL(CONVERT(VARCHAR(30), @Plan_Pull_Date_Start, 21), '')

			UPDATE t
			SET Plan_Pull_Date_Start = @Plan_Pull_Date_Start --ISNULL(@Plan_Pull_Date_Start, GETDATE())
				,Plan_Pull_Date_End = @Plan_Pull_Date_End
				,Plan_Cut_Date_Start = @Plan_Cut_Date_Start
				,Plan_Cut_Date_End = @Plan_Cut_Date_End
				,Act_Cut_Date_Start = @Plan_Cut_Date_Start
				,Act_Cut_Date_End = @Plan_Cut_Date_End
			FROM #SPD_Order_Scheduling_idx t
			WHERE RID = @RID

			--SELECT @JsonStr = ''
			--SELECT @JsonStr = (
			--		SELECT TOP 1 *
			--		FROM #SPD_Order_Scheduling_idx
			--		WHERE RID = @RID
			--		FOR JSON PATH
			--		)
			SELECT @Action_Message = N'计算拉布计划时间,' + ISNULL(@Step, '')

			--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
			--	,@Action_ID = 'JobSeq'
			--	,@Action_Type = 'AllocatedSPDTime_End'
			--	,@Action_Message = @Action_Message -- N'计算拉布计划时间'+@Step
			SELECT @Action_ID = 'JobSeq'
				,@Action_Type = 'AllocatedSPDTime_End'

			--,@Action_Message = @Cut_Action_Message
			INSERT INTO #SPD_Order_Scheduling_log (
				RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID
				,Action_Type
				,Action_Date
				,Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
				)
			SELECT RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID = @Action_ID
				,Action_Type = @Action_Type
				,Action_Date = GETDATE()
				,Action_Message = @Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No = SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
			FROM #SPD_Order_Scheduling_idx
			WHERE RID = @RID

			--END
			UPDATE S
			SET Order_Status_Type = CASE 
					WHEN Limit_Completed_Time <= dbo.fn_CCT_GetEndTimeNew(dateadd(SECOND, pull_date_Min * 60.00, ISNULL(@Plan_Pull_Date_End, GETDATE())),pull_date_Min)
						THEN 3
					ELSE S.Order_Status_Type
					END
			FROM #SPD_Order_Scheduling S
			INNER JOIN #TB_Calculate_Inserting_Info I ON S.MO_NO = I.MO_NO
				AND S.Table_No = I.Table_No
				AND S.Spd_Type = I.Spd_Type
			--LEFT JOIN #TB_SpreadMachine M WITH (NOLOCK) ON M.SpreadMachine_No = S.SpreadMachine_No
			WHERE I.SpreadMachine_No = @SpreadMachine_No
				AND S.Order_Status_Type > 3

			UPDATE #SPD_Order_Scheduling
			SET Order_Status = 'D'
				,Plan_Date = @Spread_Plan_Date
			WHERE Order_Status_Type = 3

			--判断是否存在后拉
			IF EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M ON M.MST_RID = S.RID
						AND M.DTL_RID = @RID
					WHERE Data_Type = 'LastCut'
						AND S.Plan_Pull_Date_Start IS NULL
					)
				AND NOT EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M.Data_Type
						AND M2.MST_RID = M.MST_RID
						AND M2.DTL_RID = S.RID
					WHERE M.Data_Type = 'LastCut'
						AND S.Plan_Pull_Date_Start IS NULL
					)
			BEGIN
				--重新找到最后的拉布机
				SELECT @LastCut_SpreadMachine_No = ''
					,@LastCut_CutMachine_No = ''
					,@Plan_Pull_Date_Start = NULL
					,@RID_26 = ''

				SELECT TOP 1 @LastCut_SpreadMachine_No = SpreadMachine_No
					,@LastCut_CutMachine_No = CutMachine_No
					,@Plan_Pull_Date_Start = Plan_Pull_Date_End
					,@RID_26 = S.RID
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
				INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M.Data_Type
					AND M2.MST_RID = M.MST_RID
					AND M2.DTL_RID = S.RID
				WHERE M.Data_Type = 'LastCut'
					AND S.Plan_Pull_Date_Start IS NOT NULL
				ORDER BY S.Plan_Pull_Date_End DESC

				UPDATE S
				SET SpreadMachine_No = @LastCut_SpreadMachine_No
					,CutMachine_No = @LastCut_CutMachine_No
					,S.Is_Now = 1
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					AND M.MST_RID = S.RID
				WHERE Data_Type = 'LastCut'

				--UPDATE S
				--SET S.Plan_Pull_Date_Start = NULL
				--	,S.Plan_Pull_Date_End = NULL
				SELECT @RID_25 = ''

				SELECT TOP 1 @RID_25 = RID
				FROM #SPD_Order_Scheduling_idx S
				WHERE @LastCut_SpreadMachine_No = SpreadMachine_No
					AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
					AND Plan_Date = @Spread_Plan_Date
				ORDER BY Plan_Pull_Date_Start DESC

				--SELECT @JsonStr = ''
				--SELECT @JsonStr = (
				--		SELECT S.*
				--		FROM #SPD_Order_Scheduling_idx S
				--		INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
				--			AND M.MST_RID = S.RID
				--		WHERE Data_Type = 'LastCut'
				--		FOR JSON PATH
				--		)
				SELECT @Action_Message = N'后拉锁定在@RID_26=' + ISNULL(@RID_26, '') + N'后面,原后面存在@RID_25=' + ISNULL(@RID_25, '')

				--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
				--	,@Action_ID = 'JobSeq'
				--	,@Action_Type = 'LastCutLock2'
				--	,@Action_Message = @Action_Message
				SELECT @Action_ID = 'JobSeq'
					,@Action_Type = 'LastCutLock2'

				--,@Action_Message = @Cut_Action_Message
				INSERT INTO #SPD_Order_Scheduling_log (
					RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID
					,Action_Type
					,Action_Date
					,Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
					)
				SELECT S.RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,S.Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID = @Action_ID
					,Action_Type = @Action_Type
					,Action_Date = GETDATE()
					,Action_Message = @Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No = SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					AND M.MST_RID = S.RID
				WHERE Data_Type = 'LastCut'
					--SELECT *
			END

			--判断是否存在合拉
			IF EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M ON M.MST_RID = S.RID
						AND M.DTL_RID = @RID
					WHERE M.Data_Type = 'MergeCut'
						AND S.Plan_Pull_Date_Start IS NULL
					)
				AND NOT EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M2.Data_Type
						AND M2.MST_RID = M.MST_RID
						AND M2.DTL_RID = S.RID
					WHERE M.Data_Type = 'MergeCut'
						AND S.Plan_Pull_Date_Start IS NULL
					)
			BEGIN
				--重新找到最后的拉布机
				SELECT @LastCut_SpreadMachine_No = ''
					,@LastCut_CutMachine_No = ''
					,@RID_26 = ''

				SELECT TOP 1 @LastCut_SpreadMachine_No = SpreadMachine_No
					,@LastCut_CutMachine_No = CutMachine_No
					,@Plan_Pull_Date_Start = Plan_Pull_Date_End
					,@RID_26 = S.RID
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
				INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M2.Data_Type
					AND M2.MST_RID = M.MST_RID
					AND M2.DTL_RID = S.RID
				WHERE M.Data_Type = 'MergeCut'
					AND S.Plan_Pull_Date_Start IS NOT NULL
				ORDER BY S.Plan_Pull_Date_End DESC

				UPDATE S
				SET SpreadMachine_No = @LastCut_SpreadMachine_No
					,CutMachine_No = @LastCut_CutMachine_No
					,S.Is_Now = 1
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					AND M.MST_RID = S.RID
				WHERE Data_Type = 'MergeCut'

				SELECT @RID_25 = ''

				SELECT TOP 1 @RID_25 = RID
				FROM #SPD_Order_Scheduling_idx S
				WHERE @LastCut_SpreadMachine_No = SpreadMachine_No
					AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
					AND Plan_Date = @Spread_Plan_Date
				ORDER BY Plan_Pull_Date_Start DESC

				--SELECT @JsonStr = ''
				--SELECT @JsonStr = (
				--		SELECT S.*
				--		FROM #SPD_Order_Scheduling_idx S
				--		INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
				--			AND M.MST_RID = S.RID
				--		WHERE Data_Type = 'MergeCut'
				--		FOR JSON PATH
				--		)
				SELECT @Action_Message = N'合拉锁定在@RID_26=' + ISNULL(@RID_26, '') + N'后面,原后面存在@RID_25=' + ISNULL(@RID_25, '')

				--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
				--	,@Action_ID = 'JobSeq'
				--	,@Action_Type = 'MergeCutLock2'
				--	,@Action_Message = @Action_Message
				SELECT @Action_ID = 'JobSeq'
					,@Action_Type = 'MergeCutLock2'

				--,@Action_Message = @Cut_Action_Message
				INSERT INTO #SPD_Order_Scheduling_log (
					RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID
					,Action_Type
					,Action_Date
					,Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
					)
				SELECT S.RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,S.Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID = @Action_ID
					,Action_Type = @Action_Type
					,Action_Date = GETDATE()
					,Action_Message = @Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No = SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					AND M.MST_RID = S.RID
				WHERE Data_Type = 'MergeCut'
					--UPDATE S
					--SET S.Plan_Pull_Date_Start = NULL
					--	,S.Plan_Pull_Date_End = NULL
					--FROM #SPD_Order_Scheduling_idx S
					--WHERE SpreadMachine_No = @LastCut_SpreadMachine_No
					--	AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
			END

			--判断是否存在合缸
			IF EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.MST_RID = S.RID
						AND M.DTL_RID = @RID
					WHERE M.Data_Type = 'MergeBatch'
						AND S.Plan_Pull_Date_Start IS NULL
					)
				AND NOT EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M2.Data_Type
						AND M2.MST_RID = M.MST_RID
						AND M2.DTL_RID = S.RID
					WHERE M.Data_Type = 'MergeBatch'
						AND S.Plan_Pull_Date_Start IS NULL
					)
			BEGIN
				--重新找到最后的拉布机
				SELECT @LastCut_SpreadMachine_No = ''
					,@LastCut_CutMachine_No = ''
					,@RID_26 = ''

				SELECT TOP 1 @LastCut_SpreadMachine_No = SpreadMachine_No
					,@LastCut_CutMachine_No = CutMachine_No
					,@Plan_Pull_Date_Start = Plan_Pull_Date_End
					,@RID_26 = S.RID
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
				INNER JOIN SPD_Merge_Table_Info M2 WITH (NOLOCK) ON M.Data_Type = M2.Data_Type
					AND M2.MST_RID = M.MST_RID
					AND M2.DTL_RID = S.RID
				WHERE M.Data_Type = 'MergeBatch'
					AND S.Plan_Pull_Date_Start IS NOT NULL
				ORDER BY S.Plan_Pull_Date_End DESC

				UPDATE S
				SET SpreadMachine_No = @LastCut_SpreadMachine_No
					,CutMachine_No = @LastCut_CutMachine_No
					,S.Is_Now = 1
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					AND M.MST_RID = S.RID
				WHERE Data_Type = 'MergeBatch'

				SELECT @RID_25 = ''

				SELECT TOP 1 @RID_25 = RID
				FROM #SPD_Order_Scheduling_idx S
				WHERE @LastCut_SpreadMachine_No = SpreadMachine_No
					AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
					AND Plan_Date = @Spread_Plan_Date
				ORDER BY Plan_Pull_Date_Start DESC

				--SELECT @JsonStr = ''
				--SELECT @JsonStr = (
				--		SELECT S.*
				--		FROM #SPD_Order_Scheduling_idx S
				--		INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
				--			AND M.MST_RID = S.RID
				--		WHERE Data_Type = 'MergeBatch'
				--		FOR JSON PATH
				--		)
				SELECT @Action_Message = N'合缸锁定在@RID_26=' + ISNULL(@RID_26, '') + N'后面,原后面存在@RID_25=' + ISNULL(@RID_25, '')

				--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
				--	,@Action_ID = 'JobSeq'
				--	,@Action_Type = 'MergeBatchLock'
				--	,@Action_Message = @Action_Message
				SELECT @Action_ID = 'JobSeq'
					,@Action_Type = 'MergeBatchLock'

				--,@Action_Message = @Cut_Action_Message
				INSERT INTO #SPD_Order_Scheduling_log (
					RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID
					,Action_Type
					,Action_Date
					,Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
					)
				SELECT S.RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,S.Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Last_Cut_RID
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Merge_RID
					,Spread_Scan_Time
					,IsLock
					,Lot_Number_Calculate
					,IsEnough_Material
					,Action_ID = @Action_ID
					,Action_Type = @Action_Type
					,Action_Date = GETDATE()
					,Action_Message = @Action_Message
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Ori_SpreadMachine_No = SpreadMachine_No
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN SPD_Merge_Table_Info M WITH (NOLOCK) ON M.DTL_RID = @RID
					AND M.MST_RID = S.RID
				WHERE M.Data_Type = 'MergeBatch'
					--UPDATE S
					--SET S.Plan_Pull_Date_Start = NULL
					--	,S.Plan_Pull_Date_End = NULL
					--FROM #SPD_Order_Scheduling_idx S
					--WHERE SpreadMachine_No = @LastCut_SpreadMachine_No
					--	AND Plan_Pull_Date_Start >= @Plan_Pull_Date_Start
			END

			--低于拉布限层时，判断是否是PadPrint床且存在相同SO+唛架文件名床次 2025-09-25
			--@SPD_Limit_Layers
			--SELECT @Plan_Layer_Qty = 0
			--	SELECT @Plan_Layer_Qty = Plan_Layer_Qty FROM #SPD_Order_Scheduling_idx WHERE RID = @RID
			--循环不停寻找 Damon gu 2025-10-09
			DECLARE @PadPrint_Quit_Index INT = 10

			WHILE 1 = 1
				AND @PadPrint_Quit_Index > 0
				AND EXISTS (
					SELECT TOP 1 1
					FROM #SPD_Order_Scheduling_idx S
					WHERE S.RID = @RID
						AND ISNULL(S.IsPadPrint, 0) = 1
					)
			BEGIN
				SELECT @PadPrint_Quit_Index = @PadPrint_Quit_Index - 1

				IF OBJECT_ID('tempdb..#SPD_Order_Scheduling_PadPrintinting') IS NOT NULL
				BEGIN
					DROP TABLE #SPD_Order_Scheduling_PadPrintinting
				END

				SELECT S1.*
				INTO #SPD_Order_Scheduling_PadPrintinting
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN #SPD_Order_Scheduling_idx S1 ON S.SO_No = S1.SO_No
					AND S.Marker_No = S1.Marker_No
					AND ISNULL(S1.SpreadMachine_No, '') = ''
					AND S.Plan_Date = S1.Plan_Date
				WHERE S.RID = @RID
					AND ISNULL(S.IS_Last_Cut, 0) = 0
					AND ISNULL(S.IS_Merge_Cut, 0) = 0
					AND ISNULL(S1.PadPrinting_Together_RID, '') = ''
					AND ISNULL(S.IsPadPrint, 0) = 1
					AND ISNULL(S1.IsPadPrint, 0) = 1
					AND ISNULL(S1.IS_Last_Cut, 0) = 0
					AND ISNULL(S1.IS_Merge_Cut, 0) = 0
					AND (ISNULL(S.Plan_Layer_Qty, 0) + ISNULL(S1.Plan_Layer_Qty, 0)) <= @SPD_Limit_Layers
					AND ISNULL(S1.Plan_Layer_Qty, 0) > 0

				IF EXISTS (
						SELECT TOP 1 1
						FROM #SPD_Order_Scheduling_PadPrintinting
						)
				BEGIN
					SELECT @PadPrint_RID = ''
						,@Group_RID = CONVERT(VARCHAR(50), NEWID())
						,@Plan_Layer_Qty = 0
						,@pull_date_Min = 0
						,@Cut_date_Min = 0

					SELECT TOP 1 @PadPrint_RID = RID
						,@Plan_Layer_Qty = Plan_Layer_Qty
						,@pull_date_Min = pull_date_Min
						,@Cut_date_Min = Cut_date_Min
					FROM #SPD_Order_Scheduling_PadPrintinting S
					WHERE Plan_Pull_Date_Start IS NULL
						AND ISNULL(CutMachine_No, '') <> ''
						AND ISNULL(SpreadMachine_No, '') = ''
					ORDER BY ISNULL(S.Is_Now, 0) DESC
						,CASE 
							WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
								THEN 0
							ELSE 1
							END
						,isnull(Order_Status_Type, 99)
						,CASE 
							WHEN isnull(Order_Status_Type, 99) = 2
								THEN S.SeqNO
							ELSE 999
							END
						,PLAN_DATE
						,[IsEnough_Material] DESC
						,CASE 
							WHEN isnull(Paper_Sample, '') <> ''
								THEN 0
							ELSE 1
							END
						,CASE 
							WHEN isnull(Bar_Code, '') <> ''
								THEN 0
							ELSE 1
							END
						,[Priority_Level]
						--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
						,ISNULL(IS_Last_Cut, 0)
						,S.Plan_Layer_Qty DESC

					UPDATE #SPD_Order_Scheduling_idx
					SET PadPrinting_Together_RID = @RID
						,Plan_Layer_Qty = ISNULL(Plan_Layer_Qty, 0) + @Plan_Layer_Qty
						,pull_date_Min = ISNULL(pull_date_Min, 0) + ISNULL(@pull_date_Min, 0)
						,Cut_date_Min = ISNULL(Cut_date_Min, 0) + ISNULL(@Cut_date_Min, 0)
					WHERE RID = @RID

					--更新最新结束时间
					UPDATE #SPD_Order_Scheduling_idx
					SET Plan_Pull_Date_End = [dbo].[fn_CCT_GetEndTimeNew](dateadd(SECOND, isnull(pull_date_Min, 0) * 60.00, ISNULL(Plan_Pull_Date_Start, GETDATE())),pull_date_Min)
						,Plan_Cut_Date_End = [dbo].[fn_CCT_GetEndTimeNew](dateadd(SECOND, isnull(cut_date_Min, 0) * 60.00, ISNULL(Plan_Cut_Date_Start, GETDATE())),cut_date_Min)
					WHERE RID = @RID

					--SELECT * FROM #SPD_Order_Scheduling_idx WHERE RID = @RID
					UPDATE S
					SET SpreadMachine_No = M.SpreadMachine_No
						,CutMachine_No = M.CutMachine_No
						--,S.Is_Now = 1
						,S.PadPrinting_Together_RID = @RID
						,Plan_Layer_Qty = 0
						,Plan_Pull_Date_Start = M.Plan_Pull_Date_End
						,Plan_Pull_Date_End = M.Plan_Pull_Date_End
						,pull_date_Min = 0
						,cut_date_Min = 0
						,Plan_Cut_Date_Start = M.Plan_Cut_Date_End
						,Plan_Cut_Date_End = M.Plan_Cut_Date_End
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN #SPD_Order_Scheduling_idx M WITH (NOLOCK) ON M.RID = @RID
					WHERE S.RID = @PadPrint_RID

					--SELECT @JsonStr = ''
					--SELECT @JsonStr = (
					--		SELECT S.*
					--		FROM #SPD_Order_Scheduling_idx S
					--		WHERE RID IN (
					--				@PadPrint_RID
					--				,@RID
					--				)
					--		FOR JSON PATH
					--		)
					SELECT @Action_Message = N'PadPrinting_Merge合床，@PadPrint_RID=' + ISNULL(@PadPrint_RID, '') + N' follow @RID=' + ISNULL(@RID, '')

					--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
					--	,@Action_ID = 'JobSeq'
					--	,@Action_Type = 'PadPrinting_Merge'
					--	,@Action_Message = @Action_Message
					SELECT @Action_ID = 'JobSeq'
						,@Action_Type = 'PadPrinting_Merge'

					--,@Action_Message = @Cut_Action_Message
					INSERT INTO #SPD_Order_Scheduling_log (
						RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID
						,Action_Type
						,Action_Date
						,Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
						)
					SELECT RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID = @Action_ID
						,Action_Type = @Action_Type
						,Action_Date = GETDATE()
						,Action_Message = @Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No = SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
					FROM #SPD_Order_Scheduling_idx
					WHERE RID IN (
							@PadPrint_RID
							,@RID
							)
				END
				ELSE
				BEGIN
					BREAK;
				END
			END

			--Damon gu 2025/10/20 同制单同缸合并逻辑参数控制
			IF EXISTS (
					SELECT TOP 1 1
					FROM System_Table WITH (NOLOCK)
					WHERE SYS_CODE = 'CCT_JobSeq_LogicControl'
						AND Sys_Sdescription = N'SameBatchMoTogether'
						AND ISNULL(SYS_VALUE, '0') = '1'
					)
			BEGIN
				--低于拉布限层时，同MO同缸合并
				IF OBJECT_ID('tempdb..#SPD_Order_Scheduling_MoBatch') IS NOT NULL
				BEGIN
					DROP TABLE #SPD_Order_Scheduling_MoBatch
				END

				SELECT S1.*
				INTO #SPD_Order_Scheduling_MoBatch
				FROM #SPD_Order_Scheduling_idx S
				INNER JOIN #SPD_Order_Scheduling_idx S1 ON S.MO_NO = S1.MO_NO
					AND S.Batch_No = S1.Batch_No
					AND ISNULL(S1.SpreadMachine_No, '') = ''
					AND S.Plan_Date = S1.Plan_Date
				WHERE S.RID = @RID
					AND ISNULL(S.IS_Last_Cut, 0) = 0
					AND ISNULL(S.IS_Merge_Cut, 0) = 0
					AND ISNULL(S.Group_RID, '') = ''
					AND ISNULL(S1.IS_Last_Cut, 0) = 0
					AND ISNULL(S1.IS_Merge_Cut, 0) = 0
					AND (ISNULL(S.Plan_Layer_Qty, 0) + ISNULL(S1.Plan_Layer_Qty, 0)) <= @SPD_Limit_Layers

				IF EXISTS (
						SELECT TOP 1 1
						FROM #SPD_Order_Scheduling_MoBatch
						)
				BEGIN
					SELECT @PadPrint_RID = ''
						,@Group_RID = CONVERT(VARCHAR(50), NEWID())

					SELECT TOP 1 @PadPrint_RID = RID
					FROM #SPD_Order_Scheduling_MoBatch S
					WHERE Plan_Pull_Date_Start IS NULL
						AND ISNULL(CutMachine_No, '') <> ''
						AND ISNULL(SpreadMachine_No, '') = ''
					ORDER BY ISNULL(S.Is_Now, 0) DESC
						,CASE 
							WHEN ISNULL(SpreadMachine_No, '') = @SpreadMachine_No
								THEN 0
							ELSE 1
							END
						,isnull(Order_Status_Type, 99)
						,CASE 
							WHEN isnull(Order_Status_Type, 99) = 2
								THEN S.SeqNO
							ELSE 999
							END
						,PLAN_DATE
						,[IsEnough_Material] DESC
						,CASE 
							WHEN isnull(Paper_Sample, '') <> ''
								THEN 0
							ELSE 1
							END
						,CASE 
							WHEN isnull(Bar_Code, '') <> ''
								THEN 0
							ELSE 1
							END
						,[Priority_Level]
						--,(isnull(Used_Length, 0) - isnull(Allocate_Length, 0))
						,ISNULL(IS_Last_Cut, 0)
						,ISNULL(S.Plan_Layer_Qty, 0) DESC

					UPDATE S
					SET SpreadMachine_No = M.SpreadMachine_No
						,CutMachine_No = M.CutMachine_No
						,S.Is_Now = 1
						,S.Group_RID = @RID
					FROM #SPD_Order_Scheduling_idx S
					INNER JOIN #SPD_Order_Scheduling_idx M WITH (NOLOCK) ON M.RID = @RID
					WHERE S.RID = @PadPrint_RID

					UPDATE #SPD_Order_Scheduling_idx
					SET Group_RID = @RID
					WHERE RID = @RID

					--SELECT @JsonStr = ''
					--SELECT @JsonStr = (
					--		SELECT S.*
					--		FROM #SPD_Order_Scheduling_idx S
					--		WHERE RID IN (
					--				@PadPrint_RID
					--				,@RID
					--				)
					--		FOR JSON PATH
					--		)
					SELECT @Action_Message = N'Mo_Batch_Merge同MO缸号合床，@PadPrint_RID=' + ISNULL(@PadPrint_RID, '') + N' follow @RID=' + ISNULL(@RID, '')

					--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
					--	,@Action_ID = 'JobSeq'
					--	,@Action_Type = 'Mo_Batch_Merge'
					--	,@Action_Message = @Action_Message
					SELECT @Action_ID = 'JobSeq'
						,@Action_Type = 'Mo_Batch_Merge'

					--,@Action_Message = @Cut_Action_Message
					INSERT INTO #SPD_Order_Scheduling_log (
						RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID
						,Action_Type
						,Action_Date
						,Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
						)
					SELECT RID
						,Plan_Date
						,Ori_Plan_Date
						,SpreadMachine_No
						,CutMachine_No
						,Case_Category
						,CaseNo
						,SeqNO
						,MO_NO
						,Spd_Type
						,Table_NO
						,Color_Code
						,Color_Desc
						,SO_No
						,Batch_No
						,Plan_Layer_Qty
						,Act_Layer_Qty
						,pull_date_Min
						,cut_date_Min
						,Plan_Pull_Date_Start
						,Plan_Pull_Date_End
						,Act_Pull_Date_Start
						,Act_Pull_Date_End
						,Plan_Cut_Date_Start
						,Plan_Cut_Date_End
						,Act_Cut_Date_Start
						,Act_Cut_Date_End
						,Used_Length
						,Allocate_Length
						,Input_Length
						,Rest_Minute
						,Cut_SeqNO
						,Can_Cut_Date
						,Can_Spread_Date
						,Create_Date
						,Paper_Sample
						,First_Table
						,QRTYPE
						,QR_Seq
						,Other_Main_Rid
						,IS_Last_Cut
						,Last_Cut_RID
						,Order_Status
						,Order_Status_Type
						,AddStatus
						,AddStatus_Type
						,IS_ALL_Cut
						,Priority_Level
						,Adjust_Machine_No
						,Adjust_Time
						,IS_Old_Table
						,IS_Merge_Cut
						,Merge_Cut_Remark
						,Merge_RID
						,Spread_Scan_Time
						,IsLock
						,Lot_Number_Calculate
						,IsEnough_Material
						,Action_ID = @Action_ID
						,Action_Type = @Action_Type
						,Action_Date = GETDATE()
						,Action_Message = @Action_Message
						,Group_Lot_Number
						,Marker_Width
						,Adjust_Start_Time
						,Is_Small_Order
						,Merge_Cut_RID
						,Ori_SpreadMachine_No = SpreadMachine_No
						,IsChao
						,Bar_Code
						,Is_Cut
						,Is_Now
						,IsStripe
						,IsPadPrint
						,IsAbnormal
						,Marker_No
						,Group_RID
						,PadPrinting_Together_RID
					FROM #SPD_Order_Scheduling_idx
					WHERE RID IN (
							@PadPrint_RID
							,@RID
							)
				END
			END
		END

		--SELECT @JsonStr = ''
		--SELECT @JsonStr = (
		--		SELECT S.*
		--		FROM #SPD_Order_Scheduling_idx S
		--		FOR JSON PATH
		--		)
		SELECT @Action_Message = N'排完后再调整'

		--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
		--	,@Action_ID = 'JobSeq'
		--	,@Action_Type = 'ReCalculate_Pull_Min_Begin'
		--	,@Action_Message = @Action_Message
		SELECT @Action_ID = 'JobSeq'
			,@Action_Type = 'ReCalculate_Pull_Min_Begin'

		--,@Action_Message = @Cut_Action_Message
		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = @Action_ID
			,Action_Type = @Action_Type
			,Action_Date = GETDATE()
			,Action_Message = @Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM #SPD_Order_Scheduling_idx

		--WHERE RID = @RID
		UPDATE S
		SET S.CutMachine_NO = M.CutMachine_NO
		FROM #SPD_Order_Scheduling_idx S
		INNER JOIN TB_SpreadMachine M WITH (NOLOCK) ON S.SpreadMachine_No = M.SpreadMachine_No

		--SELECT @JsonStr = ''
		--SELECT @JsonStr = (
		--		SELECT *
		--		FROM #SPD_Order_Scheduling_idx
		--		--WHERE RID = @RID
		--		FOR JSON PATH
		--		)
		--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
		--	,@Action_ID = 'JobSeq'
		--	,@Action_Type = 'UpdateSeqNo'
		--	,@Action_Message = N'根据时间更新顺序'
		SELECT @Action_ID = 'JobSeq'
			,@Action_Type = 'UpdateSeqNo'
			,@Action_Message = N'根据时间更新顺序'

		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = @Action_ID
			,Action_Type = @Action_Type
			,Action_Date = GETDATE()
			,Action_Message = @Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM #SPD_Order_Scheduling_idx

		--WHERE RID = @RID
		UPDATE D
		SET D.SeqNo = C.New_Idx
		FROM #SPD_Order_Scheduling_idx D
		INNER JOIN (
			SELECT New_Idx = ROW_NUMBER() OVER (
					PARTITION BY SpreadMachine_No ORDER BY Plan_Pull_Date_Start
					)
				,*
			FROM #SPD_Order_Scheduling_idx
			) C ON D.RID = C.RID

		UPDATE D
		SET D.Cut_SeqNO = C.New_Idx
		FROM #SPD_Order_Scheduling_idx D
		INNER JOIN (
			SELECT New_Idx = ROW_NUMBER() OVER (
					PARTITION BY CutMachine_No ORDER BY Plan_Cut_Date_Start
					)
				,*
			FROM #SPD_Order_Scheduling_idx
			) C ON D.RID = C.RID

		DECLARE @Cut_Plan_Date DATE = NULL

		--SELECT *
		--FROM #SPD_Order_Scheduling_idx
		--已完成
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'C'
		WHERE Order_Status = 'A'
			AND ISNULL(AddStatus, '') = ''

		--后拉
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D1-5'
		WHERE isnull(IS_Last_Cut, 0) = 1
			AND ISNULL(AddStatus, '') = ''
			AND ISNULL(Paper_Sample, '') <> ''
			AND ISNULL(Bar_Code, '') <> ''

		--插单
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D1-2'
		WHERE ISNULL(Adjust_Machine_No, '') <> ''
			AND ISNULL(AddStatus, '') = ''

		--当天首床
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D1-4'
		WHERE ISNULL(First_Table, 0) = 1
			AND Ori_Plan_Date = @Work_Date
			AND ISNULL(AddStatus, '') = ''

		--正常符合条件
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D1-1'
		WHERE (
				Used_Length = Allocate_Length
				AND Can_Spread_Date <= GETDATE()
				AND ISNULL(Paper_Sample, '') <> ''
				AND ISNULL(Bar_Code, '') <> ''
				)
			AND ISNULL(AddStatus, '') = ''

		--前一天
		--UPDATE #SPD_Order_Scheduling_idx
		--SET AddStatus = 'D1-3'
		--WHERE ISNULL(IS_Old_Table, 0) = 1
		--	AND ISNULL(AddStatus, '') = ''
		--已扫，正常符合条件
		--UPDATE #SPD_Order_Scheduling_idx
		--SET AddStatus = 'D1'
		--WHERE Order_Status = 'B'
		--	AND ISNULL(AddStatus, '') = ''
		--SELECT *
		--FROM system_table
		--WHERE SYS_CODE = 'AddStatusRemark'
		--无纸样，够布
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D2'
		WHERE ISNULL(Allocate_Length, 0) > 0
			AND Used_Length = ISNULL(Allocate_Length, 0)
			AND Can_Spread_Date IS NOT NULL
			AND Can_Spread_Date <= GETDATE()
			AND ISNULL(Paper_Sample, '') = ''
			AND ISNULL(AddStatus, '') = ''

		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D2-1'
		WHERE ISNULL(Allocate_Length, 0) > 0
			AND Used_Length = ISNULL(Allocate_Length, 0)
			AND Can_Spread_Date IS NOT NULL
			AND Can_Spread_Date <= GETDATE()
			AND ISNULL(Bar_Code, '') = ''
			AND ISNULL(Paper_Sample, '') <> ''
			AND ISNULL(AddStatus, '') = ''

		--有纸样，不够布
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D3'
		WHERE (
				(
					Can_Spread_Date IS NOT NULL
					AND Can_Spread_Date >= GETDATE()
					)
				OR (
					ISNULL(Allocate_Length, 0) > 0
					AND ISNULL(Allocate_Length, 0) < Used_Length
					)
				)
			AND ISNULL(Paper_Sample, '') <> ''
			--AND ISNULL(Bar_Code, '') <> ''
			AND ISNULL(AddStatus, '') = ''

		--无纸样，不够布
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D4'
		WHERE (
				(
					Can_Spread_Date IS NOT NULL
					AND Can_Spread_Date >= GETDATE()
					)
				OR (
					ISNULL(Allocate_Length, 0) > 0
					AND ISNULL(Allocate_Length, 0) < Used_Length
					)
				)
			AND ISNULL(Paper_Sample, '') = ''
			AND ISNULL(AddStatus, '') = ''

		--无唛架，不够布
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D4-1'
		WHERE (
				(
					Can_Spread_Date IS NOT NULL
					AND Can_Spread_Date >= GETDATE()
					)
				OR (
					ISNULL(Allocate_Length, 0) > 0
					AND ISNULL(Allocate_Length, 0) < Used_Length
					)
				)
			AND ISNULL(Paper_Sample, '') <> ''
			AND ISNULL(AddStatus, '') = ''
			AND ISNULL(Bar_Code, '') = ''

		--无布
		UPDATE #SPD_Order_Scheduling_idx
		SET AddStatus = 'D5'
		WHERE (
				Can_Spread_Date IS NULL
				OR ISNULL(Allocate_Length, 0) = 0
				)
			--AND ISNULL(Paper_Sample, '') = ''
			AND ISNULL(AddStatus, '') = ''

		--SELECT *
		--UPDATE S
		--SET S.Order_Status = 'C'
		--	,S.Order_Status_Type = 2
		--清掉之前的锁，重新锁
		UPDATE S
		SET S.Order_Status_Type = 99
		FROM #SPD_Order_Scheduling_idx S
		WHERE Order_Status_Type = 2

		--SELECT *
		UPDATE D
		SET D.AddStatus_Type = 1
		FROM #SPD_Order_Scheduling_idx D
		INNER JOIN System_Table ST WITH (NOLOCK) ON ST.SYS_CODE = 'AddStatusInfo'
			AND Sys_Value2 = '1'
			AND D.AddStatus = ST.Sys_Sdescription

		SELECT @Cut_Plan_Date = NULL

		SELECT @Cut_Plan_Date = MIN(PLAN_DATE)
		FROM #SPD_Order_Scheduling_idx
		WHERE Order_Status_Type > 1

		IF object_id('tempdb..#SPD_Order_Scheduling_NewLock') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_NewLock

		SELECT D.*
		INTO #SPD_Order_Scheduling_NewLock
		FROM (
			SELECT Lock_Seq = ROW_NUMBER() OVER (
					PARTITION BY SpreadMachine_No ORDER BY Plan_Pull_Date_Start
					)
				,*
			FROM #SPD_Order_Scheduling_idx
			WHERE Order_Status_Type > 1
				AND PLAN_DATE = @Cut_Plan_Date
			) D
		--INNER JOIN System_Table ST WITH (NOLOCK) ON ST.SYS_CODE = 'AddStatusInfo'
		--	AND Sys_Value2 = '1'
		--	AND D.AddStatus = ST.Sys_Sdescription
		--INNER JOIN #SPD_Order_Scheduling_idx S ON S.RID = D.RID
		WHERE D.Lock_Seq <= 2
			AND ISNULL(D.AddStatus_Type, 0) = 1

		--SELECT 
		--删除后拉没拉完的后拉
		IF object_id('tempdb..#SPD_Order_Scheduling_LastCutNotLock') IS NOT NULL
			DROP TABLE #SPD_Order_Scheduling_LastCutNotLock

		--DELETE L
		SELECT L.*
		INTO #SPD_Order_Scheduling_LastCutNotLock
		FROM #SPD_Order_Scheduling_NewLock L
		INNER JOIN #SPD_Order_Scheduling_idx S ON L.MO_NO = S.MO_NO
			AND L.Batch_No = S.Batch_No
			AND S.RID <> L.RID
			AND ISNULL(S.Order_Status_Type, 0) > 1
		WHERE ISNULL(L.IS_Last_Cut, 0) = 1

		DELETE
		FROM #SPD_Order_Scheduling_NewLock
		WHERE RID IN (
				SELECT RID
				FROM #SPD_Order_Scheduling_LastCutNotLock
				)

		--SELECT @JsonStr = ''
		--SELECT @JsonStr = (
		--		SELECT TOP 1 *
		--		FROM #SPD_Order_Scheduling_LastCutNotLock
		--		FOR JSON PATH
		--		)
		--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
		--	,@Action_ID = 'JobSeq'
		--	,@Action_Type = 'LastCutHaveOtherNotLock'
		--	,@Action_Message = N'后来床次存在非后拉床次未拉'
		SELECT @Action_ID = 'JobSeq'
			,@Action_Type = 'LastCutHaveOtherNotLock'
			,@Action_Message = N'后来床次存在非后拉床次未拉'

		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = @Action_ID
			,Action_Type = @Action_Type
			,Action_Date = GETDATE()
			,Action_Message = @Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM #SPD_Order_Scheduling_LastCutNotLock

		UPDATE S
		SET S.Order_Status_Type = 2
			,Order_Status = 'C'
		FROM #SPD_Order_Scheduling_NewLock L
		INNER JOIN #SPD_Order_Scheduling_idx S ON L.RID = S.RID

		--一起做的一起锁 Damon gu 2025/09/30
		UPDATE S
		SET S.Order_Status_Type = 2
			,S.Order_Status = 'C'
		FROM #SPD_Order_Scheduling_idx S
		INNER JOIN #SPD_Order_Scheduling_idx S1 ON ISNULL(S1.Order_Status, '') = 'C'
			AND ISNULL(S.Order_Status, '') = ''
			AND (
				(
					ISNULL(S1.PadPrinting_Together_RID, '') = ISNULL(S.PadPrinting_Together_RID, '')
					AND ISNULL(S1.PadPrinting_Together_RID, '') <> ''
					)
				OR (
					ISNULL(S1.Group_RID, '') <> ''
					AND ISNULL(S1.Group_RID, '') = ISNULL(S.Group_RID, '')
					)
				)

		UPDATE #SPD_Order_Scheduling_idx
		SET Order_Status_Type = 2
		WHERE Order_Status = 'C' --标C都变成Order_Status_Type = 2

		UPDATE S
		SET S.CutMachine_No = ISNULL(SpreadMachine_No, '') + '-CUT'
		FROM #SPD_Order_Scheduling_idx S
		WHERE SpreadMachine_No IN (
				'Fry'
				,'TBD'
				)

		IF NOT EXISTS (
				SELECT TOP 1 1
				FROM #SPD_Order_Scheduling_idx
				WHERE ISNULL(SpreadMachine_No, '') = ''
				)
			OR 1 = 1
		BEGIN
			DELETE
			FROM SPD_Order_Scheduling

			INSERT INTO SPD_Order_Scheduling (
				RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Spread_Scan_Time
				,Lot_Number_Calculate
				,IsLock
				,IsEnough_Material
				,Merge_RID
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No
				,Last_Cut_rid
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
				)
			SELECT RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Spread_Scan_Time
				,Lot_Number_Calculate
				,IsLock
				,IsEnough_Material
				,Merge_RID
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No = E.SpreadMachine_No
				,Last_Cut_rid
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
			FROM (
				SELECT idx = ROW_NUMBER() OVER (
						PARTITION BY RID ORDER BY RID
						)
					,RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Spread_Scan_Time
					,Lot_Number_Calculate
					,IsLock
					,IsEnough_Material
					,Merge_RID
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Last_Cut_rid
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx
				) E
			WHERE E.IDX = 1
		END
		ELSE
		BEGIN
			INSERT INTO #SPD_Order_Scheduling_log (
				RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID
				,Action_Type
				,Action_Date
				,Action_Message
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
				)
			SELECT RID
				,Plan_Date
				,Ori_Plan_Date
				,SpreadMachine_No
				,CutMachine_No
				,Case_Category
				,CaseNo
				,SeqNO
				,MO_NO
				,Spd_Type
				,Table_NO
				,Color_Code
				,Color_Desc
				,SO_No
				,Batch_No
				,Plan_Layer_Qty
				,Act_Layer_Qty
				,pull_date_Min
				,cut_date_Min
				,Plan_Pull_Date_Start
				,Plan_Pull_Date_End
				,Act_Pull_Date_Start
				,Act_Pull_Date_End
				,Plan_Cut_Date_Start
				,Plan_Cut_Date_End
				,Act_Cut_Date_Start
				,Act_Cut_Date_End
				,Used_Length
				,Allocate_Length
				,Input_Length
				,Rest_Minute
				,Cut_SeqNO
				,Can_Cut_Date
				,Can_Spread_Date
				,Create_Date
				,Paper_Sample
				,First_Table
				,QRTYPE
				,QR_Seq
				,Other_Main_Rid
				,IS_Last_Cut
				,Last_Cut_RID
				,Order_Status
				,Order_Status_Type
				,AddStatus
				,AddStatus_Type
				,IS_ALL_Cut
				,Priority_Level
				,Adjust_Machine_No
				,Adjust_Time
				,IS_Old_Table
				,IS_Merge_Cut
				,Merge_Cut_Remark
				,Merge_RID
				,Spread_Scan_Time
				,IsLock
				,Lot_Number_Calculate
				,IsEnough_Material
				,Action_ID = 'Create'
				,Action_Type = 'P_Task_Calculate_Save'
				,Action_Date = getdate()
				,Action_Message = N'计算结束'
				,Group_Lot_Number
				,Marker_Width
				,Adjust_Start_Time
				,Is_Small_Order
				,Merge_Cut_RID
				,Ori_SpreadMachine_No = E.SpreadMachine_No
				,IsChao
				,Bar_Code
				,Is_Cut
				,Is_Now
				,IsStripe
				,IsPadPrint
				,IsAbnormal
				,Marker_No
				,Group_RID
				,PadPrinting_Together_RID
			FROM (
				SELECT idx = ROW_NUMBER() OVER (
						PARTITION BY RID ORDER BY RID
						)
					,RID
					,Plan_Date
					,Ori_Plan_Date
					,SpreadMachine_No
					,CutMachine_No
					,Case_Category
					,CaseNo
					,SeqNO
					,MO_NO
					,Spd_Type
					,Table_NO
					,Color_Code
					,Color_Desc
					,SO_No
					,Batch_No
					,Plan_Layer_Qty
					,Act_Layer_Qty
					,pull_date_Min
					,cut_date_Min
					,Plan_Pull_Date_Start
					,Plan_Pull_Date_End
					,Act_Pull_Date_Start
					,Act_Pull_Date_End
					,Plan_Cut_Date_Start
					,Plan_Cut_Date_End
					,Act_Cut_Date_Start
					,Act_Cut_Date_End
					,Used_Length
					,Allocate_Length
					,Input_Length
					,Rest_Minute
					,Cut_SeqNO
					,Can_Cut_Date
					,Can_Spread_Date
					,Create_Date
					,Paper_Sample
					,First_Table
					,QRTYPE
					,QR_Seq
					,Other_Main_Rid
					,IS_Last_Cut
					,Order_Status
					,Order_Status_Type
					,AddStatus
					,AddStatus_Type
					,IS_ALL_Cut
					,Priority_Level
					,Adjust_Machine_No
					,Adjust_Time
					,IS_Old_Table
					,IS_Merge_Cut
					,Merge_Cut_Remark
					,Spread_Scan_Time
					,Lot_Number_Calculate
					,IsLock
					,IsEnough_Material
					,Merge_RID
					,Group_Lot_Number
					,Marker_Width
					,Adjust_Start_Time
					,Is_Small_Order
					,Merge_Cut_RID
					,Last_Cut_rid
					,IsChao
					,Bar_Code
					,Is_Cut
					,Is_Now
					,IsStripe
					,IsPadPrint
					,IsAbnormal
					,Marker_No
					,Group_RID
					,PadPrinting_Together_RID
				FROM #SPD_Order_Scheduling_idx
				) E
			WHERE E.IDX = 1
		END

		--SELECT @JsonStr = ''
		--SELECT @JsonStr = (
		--		SELECT S.*
		--		FROM SPD_Order_Scheduling S WITH (NOLOCK)
		--		INNER JOIN TB_SpreadMachine M WITH (NOLOCK) ON S.SpreadMachine_No = M.SpreadMachine_No
		--		WHERE S.CutMachine_No <> M.CutMachine_NO
		--		FOR JSON PATH
		--		)
		--EXEC [dbo].[p_SPD_Order_Scheduling_log] @JsonStr = @JsonStr
		--	,@Action_ID = 'JobSeq'
		--	,@Action_Type = 'FixCutMachineNotMatch'
		--	,@Action_Message = N'拉布机对应的裁剪机不一致'
		SELECT @Action_ID = 'JobSeq'
			,@Action_Type = 'FixCutMachineNotMatch'
			,@Action_Message = N'拉布机对应的裁剪机不一致'

		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT S.RID
			,Plan_Date
			,Ori_Plan_Date
			,S.SpreadMachine_No
			,S.CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,S.Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = @Action_ID
			,Action_Type = @Action_Type
			,Action_Date = GETDATE()
			,Action_Message = @Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,S.Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No = S.SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM SPD_Order_Scheduling S WITH (NOLOCK)
		INNER JOIN TB_SpreadMachine M WITH (NOLOCK) ON S.SpreadMachine_No = M.SpreadMachine_No
		WHERE S.CutMachine_No <> M.CutMachine_NO

		UPDATE S
		SET S.CutMachine_No = M.CutMachine_NO
		FROM SPD_Order_Scheduling S
		INNER JOIN TB_SpreadMachine M ON S.SpreadMachine_No = M.SpreadMachine_No
		WHERE S.CutMachine_No <> M.CutMachine_NO

		UPDATE S
		SET S.Plan_Cut_Date_End = DATEADD(MINUTE, 22, S.Plan_Cut_Date_Start)
		FROM SPD_Order_Scheduling S
		WHERE S.Plan_Cut_Date_End IS NULL
			OR (S.Plan_Cut_Date_Start = S.Plan_Cut_Date_End)

		--alter table SPD_Order_Scheduling_log ADD Last_Cut_RID  varchar(50) null
		INSERT INTO #SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID = 'Create'
			,Action_Type = 'P_Task_Calculate_Save'
			,Action_Date = getdate()
			,Action_Message = N'计算结束'
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,S.Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM SPD_Order_Scheduling S WITH (NOLOCK)

		DECLARE @Message_TotalTime NVARCHAR(MAX) = N'@Calculate_LotNumber=' + isnull(@Calculate_LotNumber, '') + N',总耗时:' + convert(VARCHAR(50), datediff(MILLISECOND, @BeginTime, getdate()) / 1000.00 / 60.00)

		INSERT INTO LOGS (
			RID
			,UserID
			,ActionTime
			,FullURL
			,Source
			,StackTrace
			,Message
			,LogType
			)
		SELECT RID = CONVERT(VARCHAR(50), NEWID())
			,UserID = @Action_ID
			,ActionTime = GETDATE()
			,FullURL = '#TB_SpreadMachine'
			,Source = 'P_Task_Calculate'
			,StackTrace = (
				SELECT *
				FROM #TB_SpreadMachine
				FOR JSON PATH
				)
			,Message = ''
			,LogType = '10'

		--EXEC p_WeiXin_SndMsg @Title = N'CCT JOB SEQ计算任务结束'
		--	,@ToUser = 'lwzxgu'
		--	,@Description = @Message_TotalTime
		--	,@Action_ID = 'lwzxgu'
		INSERT INTO LOGS (
			RID
			,UserID
			,ActionTime
			,FullURL
			,Source
			,StackTrace
			,Message
			,LogType
			)
		SELECT RID = CONVERT(VARCHAR(50), NEWID())
			,UserID = ''
			,ActionTime = GETDATE()
			,FullURL = 'TotalTime'
			,Source = 'P_Task_Calculate'
			,StackTrace = 'TotalTime'
			,Message = @Message_TotalTime
			,LogType = ''
	END TRY

	BEGIN CATCH
		DECLARE @CCT_JOB_Error NVARCHAR(MAX) = '@Version_ServerName=' + isnull(@Version_ServerName, '') + ',@Calculate_LotNumber=' + isnull(@Calculate_LotNumber, '') + ',Error:' + ERROR_MESSAGE()

		EXEC p_WeiXin_SndMsg @Title = N'CCT JOB SEQ计算任务报错'
			,@ToUser = 'lwzxgu'
			,@Description = @CCT_JOB_Error
			,@Action_ID = 'lwzxgu'

		INSERT INTO SPD_Order_Scheduling_log (
			RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
			)
		SELECT RID
			,Plan_Date
			,Ori_Plan_Date
			,SpreadMachine_No
			,CutMachine_No
			,Case_Category
			,CaseNo
			,SeqNO
			,MO_NO
			,Spd_Type
			,Table_NO
			,Color_Code
			,Color_Desc
			,SO_No
			,Batch_No
			,Plan_Layer_Qty
			,Act_Layer_Qty
			,pull_date_Min
			,cut_date_Min
			,Plan_Pull_Date_Start
			,Plan_Pull_Date_End
			,Act_Pull_Date_Start
			,Act_Pull_Date_End
			,Plan_Cut_Date_Start
			,Plan_Cut_Date_End
			,Act_Cut_Date_Start
			,Act_Cut_Date_End
			,Used_Length
			,Allocate_Length
			,Input_Length
			,Rest_Minute
			,Cut_SeqNO
			,Can_Cut_Date
			,Can_Spread_Date
			,Create_Date
			,Paper_Sample
			,First_Table
			,QRTYPE
			,QR_Seq
			,Other_Main_Rid
			,IS_Last_Cut
			,Last_Cut_RID
			,Order_Status
			,Order_Status_Type
			,AddStatus
			,AddStatus_Type
			,IS_ALL_Cut
			,Priority_Level
			,Adjust_Machine_No
			,Adjust_Time
			,IS_Old_Table
			,IS_Merge_Cut
			,Merge_Cut_Remark
			,Merge_RID
			,Spread_Scan_Time
			,IsLock
			,Lot_Number_Calculate
			,IsEnough_Material
			,Action_ID
			,Action_Type
			,Action_Date
			,Action_Message
			,Group_Lot_Number
			,Marker_Width
			,Adjust_Start_Time
			,Is_Small_Order
			,Merge_Cut_RID
			,Ori_SpreadMachine_No
			,IsChao
			,Bar_Code
			,Is_Cut
			,Is_Now
			,IsStripe
			,IsPadPrint
			,IsAbnormal
			,Marker_No
			,Group_RID
			,PadPrinting_Together_RID
		FROM #SPD_Order_Scheduling_log

		PRINT ERROR_MESSAGE()
	END CATCH

	INSERT INTO SPD_Order_Scheduling_log (
		RID
		,Plan_Date
		,Ori_Plan_Date
		,SpreadMachine_No
		,CutMachine_No
		,Case_Category
		,CaseNo
		,SeqNO
		,MO_NO
		,Spd_Type
		,Table_NO
		,Color_Code
		,Color_Desc
		,SO_No
		,Batch_No
		,Plan_Layer_Qty
		,Act_Layer_Qty
		,pull_date_Min
		,cut_date_Min
		,Plan_Pull_Date_Start
		,Plan_Pull_Date_End
		,Act_Pull_Date_Start
		,Act_Pull_Date_End
		,Plan_Cut_Date_Start
		,Plan_Cut_Date_End
		,Act_Cut_Date_Start
		,Act_Cut_Date_End
		,Used_Length
		,Allocate_Length
		,Input_Length
		,Rest_Minute
		,Cut_SeqNO
		,Can_Cut_Date
		,Can_Spread_Date
		,Create_Date
		,Paper_Sample
		,First_Table
		,QRTYPE
		,QR_Seq
		,Other_Main_Rid
		,IS_Last_Cut
		,Last_Cut_RID
		,Order_Status
		,Order_Status_Type
		,AddStatus
		,AddStatus_Type
		,IS_ALL_Cut
		,Priority_Level
		,Adjust_Machine_No
		,Adjust_Time
		,IS_Old_Table
		,IS_Merge_Cut
		,Merge_Cut_Remark
		,Merge_RID
		,Spread_Scan_Time
		,IsLock
		,Lot_Number_Calculate
		,IsEnough_Material
		,Action_ID
		,Action_Type
		,Action_Date
		,Action_Message
		,Group_Lot_Number
		,Marker_Width
		,Adjust_Start_Time
		,Is_Small_Order
		,Merge_Cut_RID
		,Ori_SpreadMachine_No
		,IsChao
		,Bar_Code
		,Is_Cut
		,Is_Now
		,IsStripe
		,IsPadPrint
		,IsAbnormal
		,Marker_No
		,Group_RID
		,PadPrinting_Together_RID
		)
	SELECT RID
		,Plan_Date
		,Ori_Plan_Date
		,SpreadMachine_No
		,CutMachine_No
		,Case_Category
		,CaseNo
		,SeqNO
		,MO_NO
		,Spd_Type
		,Table_NO
		,Color_Code
		,Color_Desc
		,SO_No
		,Batch_No
		,Plan_Layer_Qty
		,Act_Layer_Qty
		,pull_date_Min
		,cut_date_Min
		,Plan_Pull_Date_Start
		,Plan_Pull_Date_End
		,Act_Pull_Date_Start
		,Act_Pull_Date_End
		,Plan_Cut_Date_Start
		,Plan_Cut_Date_End
		,Act_Cut_Date_Start
		,Act_Cut_Date_End
		,Used_Length
		,Allocate_Length
		,Input_Length
		,Rest_Minute
		,Cut_SeqNO
		,Can_Cut_Date
		,Can_Spread_Date
		,Create_Date
		,Paper_Sample
		,First_Table
		,QRTYPE
		,QR_Seq
		,Other_Main_Rid
		,IS_Last_Cut
		,Last_Cut_RID
		,Order_Status
		,Order_Status_Type
		,AddStatus
		,AddStatus_Type
		,IS_ALL_Cut
		,Priority_Level
		,Adjust_Machine_No
		,Adjust_Time
		,IS_Old_Table
		,IS_Merge_Cut
		,Merge_Cut_Remark
		,Merge_RID
		,Spread_Scan_Time
		,IsLock
		,Lot_Number_Calculate
		,IsEnough_Material
		,Action_ID
		,Action_Type
		,Action_Date
		,Action_Message
		,Group_Lot_Number
		,Marker_Width
		,Adjust_Start_Time
		,Is_Small_Order
		,Merge_Cut_RID
		,Ori_SpreadMachine_No
		,IsChao
		,Bar_Code
		,Is_Cut
		,Is_Now
		,IsStripe
		,IsPadPrint
		,IsAbnormal
		,Marker_No
		,Group_RID
		,PadPrinting_Together_RID
	FROM #SPD_Order_Scheduling_log

	UPDATE System_Table
	SET SYS_DATE = getdate()
		,SYS_VALUE = '0'
	WHERE SYS_CODE = 'P_Task_Calculate'

